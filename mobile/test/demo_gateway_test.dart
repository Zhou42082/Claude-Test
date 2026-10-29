import 'package:flutter_test/flutter_test.dart';
import 'package:smart_home/demo/demo_gateway.dart';
import 'package:smart_home/models/alert.dart';
import 'package:smart_home/models/device.dart';
import 'package:smart_home/services/gateway_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DemoGatewayClient demo;
  late List<GatewayEvent> events;

  setUp(() async {
    demo = DemoGatewayClient();
    events = [];
    demo.events().listen(events.add);
    await pumpEventQueue();
  });

  tearDown(() => demo.close());

  Device device(String id) =>
      events.whereType<DeviceUpdatedEvent>().map((e) => e.device).lastWhere((d) => d.id == id);
  List<GatewayAlert> alerts() => [for (final e in events.whereType<AlertEvent>()) e.alert];

  test('starts with a snapshot of the demo home', () {
    final snapshot = events.single as SnapshotEvent;
    final types = {for (final d in snapshot.devices) d.type};
    expect(
      types,
      containsAll([DeviceType.lock, DeviceType.camera, DeviceType.airPurifier, DeviceType.scene]),
    );
    expect({for (final d in snapshot.devices) d.platform}, containsAll(DevicePlatform.values.take(5)));
    expect(snapshot.alerts, isEmpty);
  });

  test('commands update state and validate input', () async {
    await demo.sendCommand('demo:bedroom_lamp', DeviceAction.setBrightness, {'brightness': 60});
    await pumpEventQueue();
    expect(device('demo:bedroom_lamp').state, containsPair('brightness', 60));
    expect(device('demo:bedroom_lamp').isOn, isTrue);

    await expectLater(
      demo.sendCommand('demo:bedroom_lamp', DeviceAction.setBrightness, {'brightness': 300}),
      throwsA(isA<GatewayException>().having((e) => e.statusCode, 'status', 422)),
    );
    await expectLater(
      demo.sendCommand('demo:kitchen_plug', DeviceAction.open),
      throwsA(isA<GatewayException>().having((e) => e.statusCode, 'status', 422)),
    );
  });

  test('unlock needs the PIN and raises an info alert', () async {
    await expectLater(
      demo.sendCommand('demo:entrance_lock', DeviceAction.unlock, {'pin': '0000'}),
      throwsA(isA<GatewayException>().having((e) => e.statusCode, 'status', 403)),
    );
    await demo.sendCommand('demo:entrance_lock', DeviceAction.unlock, {'pin': DemoGatewayClient.unlockPin});
    await pumpEventQueue();
    expect(device('demo:entrance_lock').lockState, 'unlocked');
    expect(alerts().single.message, '门锁已打开');
    expect(alerts().single.level, AlertLevel.info);
  });

  test('away scene turns things off and locks the door', () async {
    await demo.sendCommand('demo:entrance_lock', DeviceAction.unlock, {'pin': DemoGatewayClient.unlockPin});
    await pumpEventQueue();
    await demo.sendCommand('demo:scene_away', DeviceAction.activate);
    await pumpEventQueue();
    expect(device('demo:living_light').isOn, isFalse);
    expect(device('demo:living_ac').hvacMode, 'off');
    expect(device('demo:living_curtain').position, 0);
    expect(device('demo:entrance_lock').isLocked, isTrue);
  });

  test('demo scenarios raise alerts once, reset restores silently', () async {
    await demo.runDemo('demo:leak');
    await pumpEventQueue();
    await demo.runDemo('demo:leak');
    await pumpEventQueue();
    await demo.runDemo('demo:doorbell');
    await pumpEventQueue();
    await demo.runDemo('demo:filter_low');
    await pumpEventQueue();
    expect(alerts().map((a) => a.message), ['检测到漏水', '有人按门铃', '滤芯剩余 5%，请及时更换']);
    expect(alerts().first.level, AlertLevel.critical);

    await demo.runDemo('demo:reset');

    await pumpEventQueue();
    expect(alerts(), hasLength(3));
    expect(device('demo:kitchen_leak').isOn, isFalse);

    // 新的快照里带着之前的告警，最新在前
    final again = <GatewayEvent>[];
    demo.events().listen(again.add);
    await pumpEventQueue();
    expect((again.single as SnapshotEvent).alerts.first.message, '滤芯剩余 5%，请及时更换');
  });

  test('motion alerts are rate limited', () async {
    await demo.runDemo('demo:motion');
    await pumpEventQueue();
    await demo.runDemo('demo:reset');
    await pumpEventQueue();
    await demo.runDemo('demo:motion');
    await pumpEventQueue();
    expect(alerts().map((a) => a.message), ['检测到移动']);
  });

  test('PTZ changes the demo camera picture', () async {
    final before = await demo.fetchSnapshot('demo:entrance_cam');
    await demo.sendCommand('demo:entrance_cam', DeviceAction.ptz, {'direction': 'left'});
    await pumpEventQueue();
    final after = await demo.fetchSnapshot('demo:entrance_cam');
    expect(before.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    expect(after, isNot(equals(before)));
    await expectLater(demo.fetchStreamUri('demo:entrance_cam'), throwsA(isA<GatewayException>()));
  });

  test('alert rules match the gateway', () {
    Device sensor(bool on) => Device.fromJson({
      'id': 'x',
      'name': 'x',
      'type': 'binary_sensor',
      'platform': 'other',
      'state': {'on': on, 'device_class': 'gas'},
    });
    expect(detectAlerts(sensor(false), sensor(true)), [(AlertLevel.critical, '检测到燃气泄漏')]);
    expect(detectAlerts(sensor(true), sensor(true)), isEmpty);
  });
}
