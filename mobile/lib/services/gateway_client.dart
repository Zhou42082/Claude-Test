import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/device.dart';

class GatewayConfig {
  const GatewayConfig({required this.baseUrl, required this.token});

  /// 例如 http://192.168.1.10:8000
  final String baseUrl;
  final String token;

  bool get isComplete => baseUrl.isNotEmpty && token.isNotEmpty;
}

class GatewayException implements Exception {
  GatewayException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// 网关事件：snapshot（全量）、updated（单个设备变化）、removed（设备被移除）
sealed class GatewayEvent {}

class SnapshotEvent extends GatewayEvent {
  SnapshotEvent(this.devices);
  final List<Device> devices;
}

class DeviceUpdatedEvent extends GatewayEvent {
  DeviceUpdatedEvent(this.device);
  final Device device;
}

class DeviceRemovedEvent extends GatewayEvent {
  DeviceRemovedEvent(this.device);
  final Device device;
}

class GatewayClient {
  GatewayClient(this.config, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final GatewayConfig config;
  final http.Client _http;

  Uri _uri(String path) => Uri.parse('${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${config.token}',
    'Content-Type': 'application/json',
  };

  Future<List<Device>> fetchDevices() async {
    final resp = await _http.get(_uri('/api/devices'), headers: _headers);
    _check(resp);
    final list = jsonDecode(utf8.decode(resp.bodyBytes)) as List;
    return [for (final d in list) Device.fromJson(d as Map<String, dynamic>)];
  }

  Future<void> sendCommand(String deviceId, String action, [Map<String, Object?> params = const {}]) async {
    final resp = await _http.post(
      _uri('/api/devices/${Uri.encodeComponent(deviceId)}/commands'),
      headers: _headers,
      body: jsonEncode({'action': action, 'params': params}),
    );
    _check(resp);
  }

  /// 打开实时事件通道。连接断开时 Stream 结束，由调用方负责重连。
  Stream<GatewayEvent> events() {
    final base = _uri('/api/ws');
    final wsUri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      queryParameters: {'token': config.token},
    );
    final channel = WebSocketChannel.connect(wsUri);
    return channel.stream.map((raw) => _parseEvent(raw as String)).where((e) => e != null).cast();
  }

  /// 摄像头当前画面（JPEG / PNG 字节）
  Future<Uint8List> fetchSnapshot(String deviceId) async {
    final resp = await _http.get(
      _uri('/api/devices/${Uri.encodeComponent(deviceId)}/snapshot'),
      headers: {'Authorization': 'Bearer ${config.token}'},
    );
    _check(resp);
    return resp.bodyBytes;
  }

  /// 摄像头实时视频的 HLS 地址。地址中带一次性令牌，播放器不需要额外的鉴权头。
  Future<Uri> fetchStreamUri(String deviceId) async {
    final resp = await _http.post(
      _uri('/api/devices/${Uri.encodeComponent(deviceId)}/stream'),
      headers: _headers,
    );
    _check(resp);
    final path = (jsonDecode(utf8.decode(resp.bodyBytes)) as Map)['url'] as String;
    return _uri(path);
  }

  void close() => _http.close();

  GatewayEvent? _parseEvent(String raw) {
    final msg = jsonDecode(raw) as Map<String, dynamic>;
    switch (msg['type']) {
      case 'snapshot':
        return SnapshotEvent([
          for (final d in msg['devices'] as List) Device.fromJson(d as Map<String, dynamic>),
        ]);
      case 'device_updated':
        return DeviceUpdatedEvent(Device.fromJson(msg['device'] as Map<String, dynamic>));
      case 'device_removed':
        return DeviceRemovedEvent(Device.fromJson(msg['device'] as Map<String, dynamic>));
    }
    return null;
  }

  void _check(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    var message = '请求失败 (${resp.statusCode})';
    try {
      final detail = (jsonDecode(utf8.decode(resp.bodyBytes)) as Map)['detail'];
      if (detail is String) message = detail;
    } catch (_) {
      // 非 JSON 响应，保留默认提示
    }
    if (resp.statusCode == 401) message = '令牌无效，请在设置中检查';
    throw GatewayException(message, resp.statusCode);
  }
}
