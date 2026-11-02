import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../demo/demo_gateway.dart';
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
  DeviceStore({GatewayClientFactory? clientFactory, DateTime? alertsSeenUntil, this.onAlertsSeen})
    : _clientFactory = clientFactory ?? _defaultClient,
      _alertsSeenUntil = alertsSeenUntil;

  /// 告警已读位置变化时回调，用于持久化（重启 App 后旧告警不再算未读）
  final ValueChanged<DateTime>? onAlertsSeen;

  static const _maxRetryDelay = Duration(seconds: 30);

  static GatewayClient _defaultClient(GatewayConfig config) =>
      config.isDemo ? DemoGatewayClient() : GatewayClient(config);

  bool _demo = false;

  /// 当前连接的是内置演示网关
  bool get isDemo => _demo;
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
    onAlertsSeen?.call(_alertsSeenUntil!);
    notifyListeners();
  }

  /// 刚推送过来、需要弹出提示的告警（警告和紧急），读取后清空
  GatewayAlert? takeIncomingAlert() {
    final a = _incomingAlert;
    _incomingAlert = null;
    return a;
  }

  List<DemoScenario> _demoScenarios = const [];

  /// 网关处于演示模式时提供的模拟场景（漏水、门铃等）
  List<DemoScenario> get demoScenarios => _demoScenarios;

  Future<bool> runDemo(DemoScenario scenario) async {
    try {
      await _requireClient().runDemo(scenario.id);
      return true;
    } catch (e) {
      _error = '演示「${scenario.name}」失败：$e';
      notifyListeners();
      return false;
    }
  }

  DevicePlatform? _platformFilter;
  DevicePlatform? get platformFilter => _platformFilter;
  set platformFilter(DevicePlatform? value) {
    _platformFilter = value;
    notifyListeners();
  }

  bool isPending(String deviceId) => _pending.contains(deviceId);

  Device? device(String id) => _devices[id];

  /// 首页概览：室内环境与设备概况
  HomeSummary get summary {
    final devices = _devices.values.where((d) => d.type != DeviceType.scene).toList();
    num? sensor(String deviceClass) {
      for (final d in devices) {
        final value = d.state['value'];
        if (d.online &&
            d.type == DeviceType.sensor &&
            d.state['device_class'] == deviceClass &&
            value is num) {
          return value;
        }
      }
      return null;
    }

    final purifierPm25 = devices.where((d) => d.online && d.pm25 != null).map((d) => d.pm25).firstOrNull;
    return HomeSummary(
      temperature: sensor('temperature')?.toDouble(),
      humidity: sensor('humidity')?.toDouble(),
      pm25: purifierPm25 ?? sensor('pm25')?.toDouble(),
      total: devices.length,
      online: devices.where((d) => d.online).length,
      active: devices
          .where((d) => d.online && d.isOn && (d.hasPowerSwitch || d.type == DeviceType.climate))
          .length,
      alarms: devices.where((d) => d.online && d.isAlarm).length,
      urgentAlerts: _alerts.where((a) => a.level != AlertLevel.info && _isUnread(a)).length,
    );
  }

  bool _isUnread(GatewayAlert alert) {
    final seen = _alertsSeenUntil;
    return seen == null || alert.time.isAfter(seen);
  }

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
    _demo = config.isDemo;
    _devices.clear();
    _alerts.clear();
    _demoScenarios = const [];
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
        _loadDemoScenarios();
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

  Future<void> _loadDemoScenarios() async {
    final client = _client;
    if (client == null) return;
    try {
      final scenarios = await client.fetchDemoScenarios();
      if (!identical(client, _client)) return;
      _demoScenarios = scenarios;
      notifyListeners();
    } catch (_) {
      // 演示工具是可选功能，拿不到就不显示
    }
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

class HomeSummary {
  const HomeSummary({
    required this.total,
    required this.online,
    required this.active,
    required this.alarms,
    required this.urgentAlerts,
    this.temperature,
    this.humidity,
    this.pm25,
  });

  final double? temperature;
  final double? humidity;
  final double? pm25;
  final int total;
  final int online;

  /// 正在运行的灯、开关、空调等
  final int active;

  /// 正处于报警状态的设备
  final int alarms;

  /// 未读的警告 / 紧急告警
  final int urgentAlerts;

  bool get allGood => alarms == 0 && urgentAlerts == 0 && online == total;
}
