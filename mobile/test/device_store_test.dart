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
}
