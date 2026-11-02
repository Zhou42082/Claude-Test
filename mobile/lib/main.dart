import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/app_shell.dart';
import 'screens/settings_screen.dart';
import 'state/device_store.dart';
import 'state/settings_store.dart';
import 'demo_only.dart';
import 'services/gateway_client.dart';
import 'theme/app_theme.dart';
import 'web_fonts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsStore();
  final (_, webFontLoaded) = await (settings.load(), loadWebFonts()).wait;
  if (demoOnlyBuild && !settings.config.isComplete) await settings.save(GatewayConfig.demo);
  runApp(SmartHomeApp(settings: settings, fontFamily: webFontLoaded ? webFontFamily : null));
}

class SmartHomeApp extends StatelessWidget {
  const SmartHomeApp({super.key, required this.settings, this.deviceStore, this.fontFamily});

  final SettingsStore settings;

  /// 网页版加载的中文字体；手机上用系统字体
  final String? fontFamily;

  /// 测试时可注入
  final DeviceStore? deviceStore;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(
          create: (_) {
            final store =
                deviceStore ??
                DeviceStore(alertsSeenUntil: settings.alertsSeenUntil, onAlertsSeen: settings.saveAlertsSeen);
            if (deviceStore == null && settings.config.isComplete) store.connect(settings.config);
            return store;
          },
        ),
      ],
      child: MaterialApp(
        title: '智能家居',
        debugShowCheckedModeBanner: false,
        // 系统控件（返回按钮、对话框按钮、日期等）使用中文
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light(fontFamily: fontFamily),
        darkTheme: AppTheme.dark(fontFamily: fontFamily),
        home: Consumer<SettingsStore>(
          builder: (_, s, _) => s.config.isComplete ? const AppShell() : const SettingsScreen(firstRun: true),
        ),
      ),
    );
  }
}
