import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_home/main.dart';
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
}
