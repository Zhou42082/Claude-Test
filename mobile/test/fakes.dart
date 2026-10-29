import 'dart:async';

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
