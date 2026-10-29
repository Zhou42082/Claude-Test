import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_home/main.dart';
import 'package:smart_home/models/device.dart';
import 'package:smart_home/services/gateway_client.dart';
import 'package:smart_home/state/device_store.dart';
import 'package:smart_home/state/settings_store.dart';

import 'fakes.dart';

void main() {
  testWidgets('shows settings on first run', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsStore();
    await settings.load();

    await tester.pumpWidget(SmartHomeApp(settings: settings, deviceStore: DeviceStore()));
    expect(find.text('连接家庭网关'), findsOneWidget);
  });

  testWidgets('lists devices and toggles power from the card', (tester) async {
    SharedPreferences.setMockInitialValues({'gateway_url': testConfig.baseUrl, 'gateway_token': 't'});
    final settings = SettingsStore();
    await settings.load();
    final client = FakeGatewayClient();
    final store = DeviceStore(clientFactory: (_) => client)..connect(settings.config);

    await tester.pumpWidget(SmartHomeApp(settings: settings, deviceStore: store));
    client.emit(SnapshotEvent([lamp(), thermometer()]));
    await tester.pumpAndSettle();

    expect(find.text('床头灯'), findsOneWidget);
    expect(find.text('24.6°C'), findsOneWidget);
    expect(find.text('卧室'), findsWidgets);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(client.commands.single.$2, 'turn_on');

    // 打开控制面板
    await tester.tap(find.text('床头灯'));
    await tester.pumpAndSettle();
    expect(find.text('亮度'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('unlock asks for PIN and sends it to the gateway', (tester) async {
    final (client, _) = await pumpWithDevices(tester, [frontLock()]);
    expect(find.text('已上锁 · 电量 76%'), findsOneWidget);

    await tester.tap(find.text('入户门锁'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('远程开锁'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '2468');
    await tester.tap(find.widgetWithText(FilledButton, '开锁'));
    await tester.pumpAndSettle();
    final (id, action, params) = client.commands.single;
    expect((id, action), ('ha:lock.front', 'unlock'));
    expect(params, {'pin': '2468'});
  });

  testWidgets('cancelling the PIN dialog sends nothing', (tester) async {
    final (client, _) = await pumpWithDevices(tester, [frontLock()]);
    await tester.tap(find.text('入户门锁'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('远程开锁'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(client.commands, isEmpty);
  });

  testWidgets('purifier shows air quality and switches preset', (tester) async {
    final (client, _) = await pumpWithDevices(tester, [purifier()]);
    await tester.tap(find.text('净化器'));
    await tester.pumpAndSettle();

    expect(find.text('82'), findsOneWidget);
    expect(find.text('轻度污染 · µg/m³'), findsOneWidget);
    expect(find.text('8%'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '睡眠'));
    await tester.pumpAndSettle();
    final (_, action, params) = client.commands.single;
    expect(action, 'set_preset_mode');
    expect(params, {'preset_mode': 'sleep'});
  });

  testWidgets('camera sheet loads snapshot and offers live view', (tester) async {
    final (client, _) = await pumpWithDevices(tester, [doorCamera()]);
    await tester.tap(find.text('门口摄像头'));
    await tester.pumpAndSettle();

    expect(client.snapshotCalls, 1);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('实时画面'), findsOneWidget);

    await tester.tap(find.text('刷新画面'));
    await tester.pumpAndSettle();
    expect(client.snapshotCalls, 2);
  });

  testWidgets('scene chip runs the scene', (tester) async {
    final (client, _) = await pumpWithDevices(tester, [lamp(), awayScene()]);
    await tester.tap(find.widgetWithText(ActionChip, '离家'));
    await tester.pumpAndSettle();
    expect(client.commands.single.$2, 'activate');
    expect(find.text('已执行「离家」'), findsOneWidget);
  });

  testWidgets('critical alert pops up, badge counts it, alerts page clears it', (tester) async {
    final (client, store) = await pumpWithDevices(tester, [lamp()]);
    expect(find.byType(Badge), findsOneWidget);
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);

    client.emit(AlertEvent(leakAlert()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // SnackBar 入场动画
    expect(find.text('厨房 · 漏水传感器：检测到漏水'), findsOneWidget);
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);

    await tester.tap(find.byTooltip('告警'));
    await tester.pumpAndSettle();
    expect(find.text('检测到漏水'), findsOneWidget);
    expect(find.text('厨房 · 漏水传感器'), findsOneWidget);
    expect(store.unreadAlerts, 0);
  });
}

Future<(FakeGatewayClient, DeviceStore)> pumpWithDevices(WidgetTester tester, List<Device> devices) async {
  SharedPreferences.setMockInitialValues({'gateway_url': testConfig.baseUrl, 'gateway_token': 't'});
  final settings = SettingsStore();
  await settings.load();
  final client = FakeGatewayClient();
  final store = DeviceStore(clientFactory: (_) => client)..connect(settings.config);
  await tester.pumpWidget(SmartHomeApp(settings: settings, deviceStore: store));
  client.emit(SnapshotEvent(devices));
  await tester.pumpAndSettle();
  return (client, store);
}
