import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/alert.dart';
import '../models/device.dart';
import '../services/gateway_client.dart';

enum ConnectionStatus { disconnected, connecting, connected }

typedef GatewayClientFactory = GatewayClient Function(GatewayConfig config);

/// 设备状态的唯一来源：通过 WebSocket 接收网关推送，命令通过 REST 下发。
///
/// 命令下发后不做本地乐观更新，界面以网关推送回来的真实状态为准，
/// 避免设备实际执行失败时界面和设备不一致。
class DeviceStore extends ChangeNotifier {
  DeviceStore({GatewayClientFactory? clientFactory}) : _clientFactory = clientFactory ?? GatewayClient.new;

  static const _maxRetryDelay = Duration(seconds: 30);
  static const _maxAlerts = 200;

  final GatewayClientFactory _clientFactory;
  GatewayClient? _client;
  StreamSubscription<GatewayEvent>? _subscription;
  Timer? _retryTimer;
  int _attempt = 0;

  final Map<String, Device> _devices = {};
  final Set<String> _pending = {};

  /// 最新在前
  final List<GatewayAlert> _alerts = [];
  DateTime? _alertsSeenUntil;
  GatewayAlert? _incomingAlert;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionStatus get status => _status;

  String? _error;

  /// 最近一次错误，读取后清空（用于 SnackBar 提示）
  String? takeError() {
    final e = _error;
    _error = null;
    return e;
  }

  List<GatewayAlert> get alerts => List.unmodifiable(_alerts);

  int get unreadAlerts {
    final seen = _alertsSeenUntil;
    return seen == null ? _alerts.length : _alerts.where((a) => a.time.isAfter(seen)).length;
  }

  void markAlertsRead() {
    if (_alerts.isEmpty || unreadAlerts == 0) return;
    _alertsSeenUntil = _alerts.first.time;
    notifyListeners();
  }

  /// 刚推送过来、需要弹出提示的告警（警告和紧急），读取后清空
  GatewayAlert? takeIncomingAlert() {
    final a = _incomingAlert;
    _incomingAlert = null;
    return a;
  }

  DevicePlatform? _platformFilter;
  DevicePlatform? get platformFilter => _platformFilter;
  set platformFilter(DevicePlatform? value) {
    _platformFilter = value;
    notifyListeners();
  }

  bool isPending(String deviceId) => _pending.contains(deviceId);

  Device? device(String id) => _devices[id];

  List<String> get rooms {
    final set = {
      for (final d in _devices.values)
        if (d.room != null) d.room!,
    };
    return set.toList()..sort();
  }

  /// 已接入的平台（用于展示筛选项）
  List<DevicePlatform> get platforms {
    final set = {
      for (final d in _devices.values)
        if (d.type != DeviceType.scene) d.platform,
    };
    return DevicePlatform.values.where(set.contains).toList();
  }

  /// room 为 null 表示全部场景；指定房间时只返回该房间的场景
  List<Device> scenesIn(String? room) =>
      _devices.values.where((d) => d.type == DeviceType.scene && (room == null || d.room == room)).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  /// room 为 null 表示全部房间。不含场景。
  List<Device> devicesIn(String? room) {
    final list =
        _devices.values
            .where((d) => d.type != DeviceType.scene)
            .where((d) => room == null || d.room == room)
            .where((d) => _platformFilter == null || d.platform == _platformFilter)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  void connect(GatewayConfig config) {
    _teardown();
    _devices.clear();
    _alerts.clear();
    _alertsSeenUntil = null;
    _client = _clientFactory(config);
    _attempt = 0;
    _listen();
  }

  void reconnect() {
    final client = _client;
    if (client == null) return;
    _subscription?.cancel();
    _retryTimer?.cancel();
    _attempt = 0;
    _listen();
  }

  /// 下发命令，返回是否被网关接受。失败原因通过 [takeError] 获取。
  Future<bool> send(Device device, String action, [Map<String, Object?> params = const {}]) async {
    final client = _client;
    if (client == null) return false;
    _pending.add(device.id);
    notifyListeners();
    try {
      await client.sendCommand(device.id, action, params);
      return true;
    } on GatewayException catch (e) {
      _error = '${device.name}：${e.message}';
      return false;
    } catch (e) {
      _error = '${device.name}：网络错误，请检查网关连接';
      return false;
    } finally {
      _pending.remove(device.id);
      notifyListeners();
    }
  }

  Future<Uint8List> snapshot(String deviceId) => _requireClient().fetchSnapshot(deviceId);

  Future<Uri> streamUri(String deviceId) => _requireClient().fetchStreamUri(deviceId);

  GatewayClient _requireClient() => _client ?? (throw GatewayException('尚未连接网关'));

  /// 开关类操作：优先使用明确的 turn_on / turn_off，避免 toggle 在状态不同步时反向操作
  Future<bool> setPower(Device device, bool on) {
    final action = on ? DeviceAction.turnOn : DeviceAction.turnOff;
    return send(device, device.can(action) ? action : DeviceAction.toggle);
  }

  void _listen() {
    _status = ConnectionStatus.connecting;
    notifyListeners();
    _subscription = _client!.events().listen(
      _onEvent,
      onError: (Object e) => _scheduleRetry(),
      onDone: _scheduleRetry,
      cancelOnError: true,
    );
  }

  void _onEvent(GatewayEvent event) {
    switch (event) {
      case SnapshotEvent(:final devices, :final alerts):
        _devices
          ..clear()
          ..addEntries(devices.map((d) => MapEntry(d.id, d)));
        _alerts
          ..clear()
          ..addAll(alerts);
        _status = ConnectionStatus.connected;
        _attempt = 0;
      case DeviceUpdatedEvent(:final device):
        _devices[device.id] = device;
      case DeviceRemovedEvent(:final device):
        _devices.remove(device.id);
      case AlertEvent(:final alert):
        _alerts.insert(0, alert);
        if (_alerts.length > _maxAlerts) _alerts.removeLast();
        if (alert.level != AlertLevel.info) _incomingAlert = alert;
    }
    notifyListeners();
  }

  void _scheduleRetry() {
    _subscription = null;
    _status = ConnectionStatus.disconnected;
    notifyListeners();
    final seconds = min(1 << _attempt, _maxRetryDelay.inSeconds);
    _attempt = min(_attempt + 1, 5);
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: seconds), _listen);
  }

  void _teardown() {
    _retryTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}
