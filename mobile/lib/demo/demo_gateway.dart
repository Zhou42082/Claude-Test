import 'dart:async';

import 'package:flutter/services.dart';

import '../models/alert.dart';
import '../models/device.dart';
import '../services/gateway_client.dart';

/// 内置演示网关：不需要任何服务器，在 App 里模拟一个家。
///
/// 设备、场景、告警规则和演示工具与网关的演示模式（backend/gateway/adapters/mock.py、
/// backend/gateway/alerts.py）保持一致，用于在没有网关时体验和测试 App。
class DemoGatewayClient extends GatewayClient {
  DemoGatewayClient() : super(GatewayConfig.demo) {
    for (final d in _seed()) {
      _devices[d['id'] as String] = d;
    }
  }

  static const unlockPin = '2468';
  static const motionDuration = Duration(seconds: 15);
  static const motionCooldown = Duration(minutes: 5);

  final Map<String, Map<String, dynamic>> _devices = {};
  final List<GatewayAlert> _alerts = [];
  final Map<String, DateTime> _lastFired = {};
  StreamController<GatewayEvent>? _events;
  Timer? _motionReset;
  int _alertId = 0;
  int _pan = 0;
  int _tilt = 0;

  Device _device(String id) => Device.fromJson(_copy(_devices[id]!));

  @override
  Future<List<Device>> fetchDevices() async => [for (final id in _devices.keys) _device(id)];

  @override
  Stream<GatewayEvent> events() {
    _events?.close();
    final controller = StreamController<GatewayEvent>();
    _events = controller;
    // 和真实网关一样，连接后先推送全量快照
    scheduleMicrotask(() {
      if (!controller.isClosed) {
        controller.add(
          SnapshotEvent([for (final id in _devices.keys) _device(id)], _alerts.reversed.toList()),
        );
      }
    });
    return controller.stream;
  }

  @override
  Future<void> sendCommand(String deviceId, String action, [Map<String, Object?> params = const {}]) async {
    final raw = _devices[deviceId];
    if (raw == null) throw GatewayException('device not found', 404);
    final device = Device.fromJson(_copy(raw));
    if (!device.can(action)) throw GatewayException('设备 ${device.name} 不支持 $action', 422);
    if (action == DeviceAction.unlock && params['pin'] != unlockPin) {
      throw GatewayException('开锁 PIN 错误', 403);
    }
    if (!device.online) throw GatewayException('设备 ${device.name} 离线', 502);

    if (action == DeviceAction.activate) {
      for (final (id, a, p) in _scenes[deviceId] ?? const <(String, String, Map<String, Object?>)>[]) {
        final target = Device.fromJson(_copy(_devices[id]!));
        if (target.online && target.can(a)) await sendCommand(id, a, p);
      }
      return;
    }

    final s = raw['state'] as Map<String, dynamic>;
    final isClimate = device.type == DeviceType.climate;
    switch (action) {
      case DeviceAction.turnOn when isClimate:
        s['hvac_mode'] = 'auto';
      case DeviceAction.turnOff when isClimate:
        s['hvac_mode'] = 'off';
      case DeviceAction.turnOn:
        s['on'] = true;
      case DeviceAction.turnOff:
        s['on'] = false;
      case DeviceAction.toggle:
        s['on'] = s['on'] != true;
      case DeviceAction.setBrightness:
        s['brightness'] = _int(params, 'brightness', 0, 100);
        s['on'] = s['brightness'] > 0;
      case DeviceAction.setColorTemp:
        s['color_temp_kelvin'] = _int(params, 'color_temp_kelvin', 1500, 9000);
      case DeviceAction.setTemperature:
        s['target_temperature'] = _int(params, 'temperature', 5, 35);
      case DeviceAction.setHvacMode:
        s['hvac_mode'] = _choice(params, 'hvac_mode', device.hvacModes);
      case DeviceAction.setFanSpeed:
        s['percentage'] = _int(params, 'percentage', 0, 100);
        s['on'] = s['percentage'] > 0;
      case DeviceAction.setPresetMode:
        s['preset_mode'] = _choice(params, 'preset_mode', device.presetModes);
      case DeviceAction.setPosition:
        s['position'] = _int(params, 'position', 0, 100);
      case DeviceAction.open:
        s['position'] = 100;
      case DeviceAction.close:
        s['position'] = 0;
      case DeviceAction.lock:
        s['lock_state'] = 'locked';
      case DeviceAction.unlock:
        s['lock_state'] = 'unlocked';
      case DeviceAction.ptz:
        final direction = _choice(params, 'direction', device.ptzDirections);
        final (dx, dy) = switch (direction) {
          'left' => (-1, 0),
          'right' => (1, 0),
          'up' => (0, -1),
          _ => (0, 1),
        };
        _pan = (_pan + dx).clamp(-2, 2);
        _tilt = (_tilt + dy).clamp(-2, 2);
    }
    _emit(deviceId, device);
  }

  @override
  Future<Uint8List> fetchSnapshot(String deviceId) async {
    if (_devices[deviceId]?['type'] != 'camera') throw GatewayException('设备 $deviceId 不是摄像头', 422);
    final data = await rootBundle.load('assets/demo_camera/p${_pan}_t$_tilt.png');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @override
  Future<Uri> fetchStreamUri(String deviceId) async => throw GatewayException('演示摄像头不支持实时视频', 502);

  @override
  Future<List<DemoScenario>> fetchDemoScenarios() async => [
    for (final e in _demoScenarios.entries) DemoScenario(e.key, e.value),
  ];

  @override
  Future<void> runDemo(String scenarioId) async {
    switch (scenarioId) {
      case 'demo:leak':
        _update('demo:kitchen_leak', {'on': true});
      case 'demo:smoke':
        _update('demo:living_smoke', {'on': true});
      case 'demo:doorbell':
        _update('demo:entrance_cam', {'last_ring': DateTime.now().toUtc().toIso8601String()});
      case 'demo:motion':
        _update('demo:entrance_cam', {'motion': true});
        _motionReset?.cancel();
        _motionReset = Timer(motionDuration, () => _update('demo:entrance_cam', {'motion': false}));
      case 'demo:lock_jam':
        _update('demo:entrance_lock', {'lock_state': 'jammed'});
      case 'demo:low_battery':
        _update('demo:entrance_lock', {'battery': 15});
      case 'demo:filter_low':
        _update('demo:bedroom_purifier', {'filter_life': 5});
      case 'demo:camera_offline':
        final before = _device('demo:entrance_cam');
        _devices['demo:entrance_cam']!['online'] = false;
        _emit('demo:entrance_cam', before);
      case 'demo:reset':
        _pan = _tilt = 0;
        _motionReset?.cancel();
        for (final fresh in _seed()) {
          final id = fresh['id'] as String;
          final before = _device(id);
          _devices[id] = fresh;
          _emit(id, before);
        }
      default:
        throw GatewayException('not found', 404);
    }
  }

  @override
  void close() {
    _motionReset?.cancel();
    _events?.close();
  }

  void _update(String id, Map<String, Object?> state) {
    final before = _device(id);
    (_devices[id]!['state'] as Map<String, dynamic>).addAll(state);
    _emit(id, before);
  }

  void _emit(String id, Device before) {
    final after = _device(id);
    _events?.add(DeviceUpdatedEvent(after));
    for (final (level, message) in detectAlerts(before, after)) {
      final key = '$id|$message';
      final cooldown = message == motionMessage ? motionCooldown : null;
      final last = _lastFired[key];
      final now = DateTime.now();
      if (cooldown != null && last != null && now.difference(last) < cooldown) continue;
      _lastFired[key] = now;
      final alert = GatewayAlert(
        id: ++_alertId,
        time: now,
        level: level,
        deviceId: id,
        deviceName: after.name,
        room: after.room,
        message: message,
      );
      _alerts.add(alert);
      _events?.add(AlertEvent(alert));
    }
  }

  static int _int(Map<String, Object?> params, String key, int min, int max) {
    final v = params[key];
    if (v is! num || v < min || v > max) throw GatewayException("参数 '$key' 必须在 $min 到 $max 之间", 422);
    return v.round();
  }

  static String _choice(Map<String, Object?> params, String key, List<String> allowed) {
    final v = params[key];
    if (v is! String || !allowed.contains(v)) throw GatewayException('不支持的取值 $v', 422);
    return v;
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> d) => {
    ...d,
    'state': Map<String, dynamic>.from(d['state'] as Map),
    'capabilities': List<String>.from(d['capabilities'] as List),
  };
}

const motionMessage = '检测到移动';

/// 告警规则，与 backend/gateway/alerts.py 的 detect_alerts 一致
List<(AlertLevel, String)> detectAlerts(Device old, Device now) {
  final found = <(AlertLevel, String)>[];
  final o = old.state, n = now.state;
  const hazards = {'moisture': '漏水', 'smoke': '烟雾', 'gas': '燃气泄漏'};
  final hazard = hazards[n['device_class']];

  if (now.type == DeviceType.binarySensor && hazard != null && n['on'] == true && o['on'] != true) {
    found.add((AlertLevel.critical, '检测到$hazard'));
  }
  if (now.type == DeviceType.lock) {
    if (n['lock_state'] == 'jammed' && o['lock_state'] != 'jammed') {
      found.add((AlertLevel.critical, '门锁卡住，请检查'));
    } else if ((n['lock_state'] == 'unlocked' || n['lock_state'] == 'open') && o['lock_state'] == 'locked') {
      found.add((AlertLevel.info, '门锁已打开'));
    }
  }
  if (now.type == DeviceType.camera) {
    if (n['last_ring'] != null && n['last_ring'] != o['last_ring']) found.add((AlertLevel.warning, '有人按门铃'));
    if (n['motion'] == true && o['motion'] != true) found.add((AlertLevel.info, motionMessage));
  }
  final security =
      now.type == DeviceType.lock ||
      now.type == DeviceType.camera ||
      (now.type == DeviceType.binarySensor && hazard != null);
  if (security && old.online && !now.online) found.add((AlertLevel.warning, '设备离线'));

  bool crossedBelow(String key, num threshold) {
    final before = o[key], after = n[key];
    return after is num && after < threshold && (before is! num || before >= threshold);
  }

  if (crossedBelow('battery', 20)) {
    found.add((AlertLevel.warning, '电量低（${(n['battery'] as num).round()}%），请更换电池或充电'));
  }
  if (crossedBelow('filter_life', 10)) {
    found.add((AlertLevel.warning, '滤芯剩余 ${(n['filter_life'] as num).round()}%，请及时更换'));
  }
  return found;
}

const _demoScenarios = {
  'demo:leak': '厨房漏水',
  'demo:smoke': '客厅烟雾报警',
  'demo:doorbell': '有人按门铃',
  'demo:motion': '门口有人经过',
  'demo:lock_jam': '门锁卡住',
  'demo:low_battery': '门锁电量低',
  'demo:filter_low': '净化器滤芯耗尽',
  'demo:camera_offline': '摄像头离线',
  'demo:reset': '全部恢复初始状态',
};

const _onOff = ['turn_on', 'turn_off', 'toggle'];

final Map<String, List<(String, String, Map<String, Object?>)>> _scenes = {
  'demo:scene_home': [
    ('demo:living_light', 'turn_on', {}),
    ('demo:living_curtain', 'open', {}),
    ('demo:living_ac', 'turn_on', {}),
  ],
  'demo:scene_away': [
    ('demo:living_light', 'turn_off', {}),
    ('demo:bedroom_lamp', 'turn_off', {}),
    ('demo:bedroom_fan', 'turn_off', {}),
    ('demo:living_ac', 'turn_off', {}),
    ('demo:kitchen_plug', 'turn_off', {}),
    ('demo:living_curtain', 'close', {}),
    ('demo:entrance_lock', 'lock', {}),
  ],
  'demo:scene_sleep': [
    ('demo:living_light', 'turn_off', {}),
    ('demo:bedroom_lamp', 'turn_off', {}),
    ('demo:living_curtain', 'close', {}),
    ('demo:bedroom_purifier', 'set_preset_mode', {'preset_mode': 'sleep'}),
  ],
};

Map<String, dynamic> _d(
  String id,
  String name,
  String type,
  String platform,
  String? room,
  Map<String, dynamic> state, [
  List<String> capabilities = const [],
  bool online = true,
]) => {
  'id': 'demo:$id',
  'name': name,
  'type': type,
  'platform': platform,
  'room': room,
  'online': online,
  'state': state,
  'capabilities': capabilities,
};

List<Map<String, dynamic>> _seed() => [
  _d(
    'living_light',
    '客厅吸顶灯',
    'light',
    'xiaomi',
    '客厅',
    {'on': true, 'brightness': 80, 'color_temp_kelvin': 4000},
    [..._onOff, 'set_brightness', 'set_color_temp'],
  ),
  _d(
    'living_ac',
    '客厅空调',
    'climate',
    'huawei',
    '客厅',
    {
      'hvac_mode': 'cool',
      'hvac_modes': ['off', 'cool', 'heat', 'auto', 'dry', 'fan_only'],
      'current_temperature': 27.5,
      'target_temperature': 25,
    },
    ['turn_on', 'turn_off', 'set_temperature', 'set_hvac_mode'],
  ),
  _d(
    'living_curtain',
    '客厅窗帘',
    'cover',
    'tuya',
    '客厅',
    {'position': 100},
    ['open', 'close', 'stop', 'set_position'],
  ),
  _d(
    'bedroom_lamp',
    '卧室床头灯',
    'light',
    'tuya',
    '卧室',
    {'on': false, 'brightness': 30},
    [..._onOff, 'set_brightness'],
  ),
  _d(
    'bedroom_fan',
    '卧室风扇',
    'fan',
    'xiaomi',
    '卧室',
    {'on': false, 'percentage': 40},
    [..._onOff, 'set_fan_speed'],
  ),
  _d('bedroom_th', '卧室温湿度计', 'sensor', 'xiaomi', '卧室', {
    'value': 24.6,
    'unit': '°C',
    'device_class': 'temperature',
  }),
  _d('kitchen_plug', '厨房智能插座', 'switch', 'huawei', '厨房', {'on': true}, _onOff),
  _d(
    'kitchen_door',
    '厨房门窗传感器',
    'binary_sensor',
    'tuya',
    '厨房',
    {'on': false, 'device_class': 'door'},
    [],
    false,
  ),
  _d(
    'entrance_cam',
    '门口摄像头',
    'camera',
    'imou',
    '门口',
    {
      'camera_state': 'idle',
      'stream_supported': false,
      'ptz_directions': ['up', 'down', 'left', 'right'],
      'last_ring': null,
      'motion': false,
    },
    ['ptz'],
  ),
  _d(
    'entrance_lock',
    '入户门锁',
    'lock',
    'desman',
    '门口',
    {'lock_state': 'locked', 'battery': 76},
    ['lock', 'unlock'],
  ),
  _d(
    'bedroom_purifier',
    '卧室空气净化器',
    'air_purifier',
    'tuya',
    '卧室',
    {
      'on': true,
      'percentage': 50,
      'preset_mode': 'auto',
      'preset_modes': ['auto', 'sleep', 'strong'],
      'pm25': 18,
      'filter_life': 63,
    },
    [..._onOff, 'set_fan_speed', 'set_preset_mode'],
  ),
  _d('kitchen_leak', '厨房水浸传感器', 'binary_sensor', 'xiaomi', '厨房', {
    'on': false,
    'device_class': 'moisture',
    'battery': 90,
  }),
  _d('living_smoke', '客厅烟雾报警器', 'binary_sensor', 'huawei', '客厅', {'on': false, 'device_class': 'smoke'}),
  _d('scene_home', '回家', 'scene', 'other', null, {}, ['activate']),
  _d('scene_sleep', '睡眠', 'scene', 'other', null, {}, ['activate']),
  _d('scene_away', '离家', 'scene', 'other', null, {}, ['activate']),
];
