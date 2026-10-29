import 'dart:async';
import 'dart:typed_data';

import 'package:smart_home/models/alert.dart';
import 'package:smart_home/models/device.dart';
import 'package:smart_home/services/gateway_client.dart';

const testConfig = GatewayConfig(baseUrl: 'http://gateway.local:8000', token: 't');

class FakeGatewayClient extends GatewayClient {
  FakeGatewayClient() : super(testConfig);

  StreamController<GatewayEvent>? controller;
  final commands = <(String, String, Map<String, Object?>)>[];
  Object? commandError;

  void emit(GatewayEvent event) => controller!.add(event);

  @override
  Stream<GatewayEvent> events() {
    controller = StreamController<GatewayEvent>();
    return controller!.stream;
  }

  @override
  Future<void> sendCommand(String deviceId, String action, [Map<String, Object?> params = const {}]) async {
    commands.add((deviceId, action, params));
    if (commandError != null) throw commandError!;
  }

  /// 1x1 透明 PNG
  static final snapshotBytes = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);
  int snapshotCalls = 0;

  @override
  Future<Uint8List> fetchSnapshot(String deviceId) async {
    snapshotCalls++;
    return snapshotBytes;
  }

  List<DemoScenario> demoScenarios = const [];
  final demoRuns = <String>[];

  /// 不能走真实网络：默认返回空列表，即非演示模式
  @override
  Future<List<DemoScenario>> fetchDemoScenarios() async => demoScenarios;

  @override
  Future<void> runDemo(String scenarioId) async => demoRuns.add(scenarioId);

  @override
  void close() {}
}

Device lamp({bool on = false, bool online = true}) => Device.fromJson({
  'id': 'ha:light.lamp',
  'name': '床头灯',
  'type': 'light',
  'platform': 'tuya',
  'room': '卧室',
  'online': online,
  'state': {'on': on, 'brightness': 40},
  'capabilities': ['turn_on', 'turn_off', 'toggle', 'set_brightness'],
});

Device thermometer() => Device.fromJson({
  'id': 'ha:sensor.temp',
  'name': '温湿度计',
  'type': 'sensor',
  'platform': 'xiaomi',
  'room': '客厅',
  'state': {'value': 24.56, 'unit': '°C', 'device_class': 'temperature'},
  'capabilities': [],
});

Device frontLock({String lockState = 'locked'}) => Device.fromJson({
  'id': 'ha:lock.front',
  'name': '入户门锁',
  'type': 'lock',
  'platform': 'desman',
  'room': '门口',
  'state': {'lock_state': lockState, 'battery': 76},
  'capabilities': ['lock', 'unlock'],
});

Device purifier() => Device.fromJson({
  'id': 'ha:fan.purifier',
  'name': '净化器',
  'type': 'air_purifier',
  'platform': 'tuya',
  'room': '卧室',
  'state': {
    'on': true,
    'percentage': 50,
    'preset_mode': 'auto',
    'preset_modes': ['auto', 'sleep'],
    'pm25': 82,
    'filter_life': 8,
  },
  'capabilities': ['turn_on', 'turn_off', 'toggle', 'set_fan_speed', 'set_preset_mode'],
});

Device doorCamera() => Device.fromJson({
  'id': 'ha:camera.door',
  'name': '门口摄像头',
  'type': 'camera',
  'platform': 'imou',
  'room': '门口',
  'state': {
    'camera_state': 'idle',
    'stream_supported': true,
    'ptz_directions': ['left', 'right'],
    'last_ring': DateTime.now().toUtc().toIso8601String(),
  },
  'capabilities': ['ptz'],
});

Device awayScene() => Device.fromJson({
  'id': 'ha:scene.away',
  'name': '离家',
  'type': 'scene',
  'platform': 'other',
  'state': {},
  'capabilities': ['activate'],
});

GatewayAlert leakAlert({int id = 1, String level = 'critical', DateTime? time}) => GatewayAlert.fromJson({
  'id': id,
  'time': (time ?? DateTime.now()).toUtc().toIso8601String(),
  'level': level,
  'device_id': 'ha:binary_sensor.leak',
  'device_name': '漏水传感器',
  'room': '厨房',
  'message': '检测到漏水',
});
