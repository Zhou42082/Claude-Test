import 'package:flutter_test/flutter_test.dart';
import 'package:smart_home/models/device.dart';
import 'package:smart_home/services/gateway_client.dart';
import 'package:smart_home/state/device_store.dart';

import 'fakes.dart';

void main() {
  late FakeGatewayClient client;
  late DeviceStore store;

  setUp(() {
    client = FakeGatewayClient();
    store = DeviceStore(clientFactory: (_) => client)..connect(testConfig);
  });

  tearDown(() => store.dispose());

  test('applies snapshot, updates and removals', () async {
    expect(store.status, ConnectionStatus.connecting);

    client.emit(SnapshotEvent([lamp(), thermometer()]));
    await pumpEventQueue();
    expect(store.status, ConnectionStatus.connected);
    expect(store.rooms, ['卧室', '客厅']);
    expect(store.devicesIn(null), hasLength(2));
    expect(store.platforms, [DevicePlatform.xiaomi, DevicePlatform.tuya]);

    client.emit(DeviceUpdatedEvent(lamp(on: true)));
    await pumpEventQueue();
    expect(store.device('ha:light.lamp')!.isOn, isTrue);

    client.emit(DeviceRemovedEvent(thermometer()));
    await pumpEventQueue();
    expect(store.devicesIn(null).map((d) => d.id), ['ha:light.lamp']);
  });

  test('platform filter narrows device list', () async {
    client.emit(SnapshotEvent([lamp(), thermometer()]));
    await pumpEventQueue();
    store.platformFilter = DevicePlatform.xiaomi;
    expect(store.devicesIn(null).map((d) => d.name), ['温湿度计']);
    expect(store.devicesIn('卧室'), isEmpty);
  });

  test('setPower prefers explicit on/off and reports errors', () async {
    await store.setPower(lamp(), true);
    expect(client.commands.single, ('ha:light.lamp', 'turn_on', const <String, Object?>{}));
    expect(store.isPending('ha:light.lamp'), isFalse);
    expect(store.takeError(), isNull);

    client.commandError = GatewayException('设备离线', 502);
    await store.send(lamp(), DeviceAction.setBrightness, {'brightness': 10});
    expect(store.takeError(), '床头灯：设备离线');
    expect(store.takeError(), isNull);
  });

  test('marks disconnected and retries when stream closes', () async {
    client.emit(SnapshotEvent([lamp()]));
    await pumpEventQueue();
    final first = client.controller!;
    await first.close();
    await pumpEventQueue();
    expect(store.status, ConnectionStatus.disconnected);
    // 断线期间保留最后已知状态
    expect(store.devicesIn(null), hasLength(1));

    store.reconnect();
    expect(store.status, ConnectionStatus.connecting);
    expect(client.controller, isNot(same(first)));
  });

  test('scenes are kept out of the device grid and platform filter', () async {
    client.emit(SnapshotEvent([lamp(), awayScene()]));
    await pumpEventQueue();
    expect(store.devicesIn(null).map((d) => d.name), ['床头灯']);
    expect(store.scenesIn(null).map((d) => d.name), ['离家']);
    expect(store.scenesIn('卧室'), isEmpty);
    expect(store.platforms, [DevicePlatform.tuya]);
  });

  test('tracks unread alerts and surfaces urgent ones', () async {
    client.emit(SnapshotEvent([lamp()], [leakAlert(time: DateTime(2026, 10, 1))]));
    await pumpEventQueue();
    expect(store.unreadAlerts, 1);
    // 快照里的历史告警不弹出提示
    expect(store.takeIncomingAlert(), isNull);

    store.markAlertsRead();
    expect(store.unreadAlerts, 0);

    client.emit(AlertEvent(leakAlert(id: 2, level: 'info')));
    await pumpEventQueue();
    expect(store.unreadAlerts, 1);
    expect(store.takeIncomingAlert(), isNull, reason: '提示级别只计入未读，不弹出');

    client.emit(AlertEvent(leakAlert(id: 3)));
    await pumpEventQueue();
    expect(store.unreadAlerts, 2);
    expect(store.alerts.map((a) => a.id), [3, 2, 1]);
    expect(store.takeIncomingAlert()!.id, 3);
    expect(store.takeIncomingAlert(), isNull);
  });

  test('send reports success', () async {
    expect(await store.send(awayScene(), DeviceAction.activate), isTrue);
    client.commandError = GatewayException('boom', 502);
    expect(await store.send(awayScene(), DeviceAction.activate), isFalse);
  });
}
