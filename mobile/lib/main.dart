import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'state/device_store.dart';
import 'state/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsStore();
  await settings.load();
  runApp(SmartHomeApp(settings: settings));
}

class SmartHomeApp extends StatelessWidget {
  const SmartHomeApp({super.key, required this.settings, this.deviceStore});

  final SettingsStore settings;

  /// 测试时可注入
  final DeviceStore? deviceStore;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D6B);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(
          create: (_) {
            final store = deviceStore ?? DeviceStore();
            if (deviceStore == null && settings.config.isComplete) store.connect(settings.config);
            return store;
          },
        ),
      ],
      child: MaterialApp(
        title: '智能家居',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
        home: Consumer<SettingsStore>(
          builder: (_, s, _) =>
              s.config.isComplete ? const HomeScreen() : const SettingsScreen(firstRun: true),
        ),
      ),
    );
  }
}
