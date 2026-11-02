import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_home/main.dart';
import 'package:smart_home/models/device.dart';
import 'package:smart_home/services/gateway_client.dart';
import 'package:smart_home/state/device_store.dart';
import 'package:smart_home/state/settings_store.dart';

import 'fakes.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

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
    await tester.tap(find.text('离家'));
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

  testWidgets('camera PTZ moves and then refreshes the snapshot', (tester) async {
    final (client, _) = await pumpWithDevices(tester, [doorCamera()]);
    await tester.tap(find.text('门口摄像头'));
    await tester.pumpAndSettle();

    expect(find.textContaining('最近门铃'), findsOneWidget);
    // 只显示摄像头支持的方向
    expect(find.byTooltip('向左'), findsOneWidget);
    expect(find.byTooltip('向上'), findsNothing);

    await tester.ensureVisible(find.byTooltip('向左'));
    await tester.tap(find.byTooltip('向左'));
    await tester.pump();
    final (_, action, params) = client.commands.single;
    expect(action, 'ptz');
    expect(params, {'direction': 'left'});
    expect(client.snapshotCalls, 1);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(client.snapshotCalls, 2);
  });

  testWidgets('demo tools appear only in demo mode and run scenarios', (tester) async {
    final (client, store) = await pumpWithDevices(tester, [lamp()]);
    expect(find.byTooltip('演示工具'), findsNothing);

    client.demoScenarios = const [DemoScenario('mock:leak', '厨房漏水')];
    client.emit(SnapshotEvent([lamp()]));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('演示工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('厨房漏水'));
    await tester.pumpAndSettle();
    expect(client.demoRuns, ['mock:leak']);
    expect(find.text('已模拟：厨房漏水'), findsOneWidget);
  });

  testWidgets('first run can start the built-in demo without a gateway', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsStore();
    await settings.load();
    await tester.pumpWidget(SmartHomeApp(settings: settings));

    await tester.scrollUntilVisible(find.text('体验演示模式'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('体验演示模式'));
    await tester.pumpAndSettle();

    expect(find.textContaining('演示模式 · 设备和数据都是模拟的'), findsOneWidget);
    expect(find.byTooltip('演示工具'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('入户门锁'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('入户门锁'), findsOneWidget);
    expect(settings.config.isDemo, isTrue);
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
