import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/alert.dart';
import '../state/device_store.dart';
import '../widgets/snack_bar_ext.dart';
import 'alerts_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'scenes_screen.dart';

/// 主框架：底部导航 首页 / 场景 / 告警 / 我的，并负责弹出错误和告警提示
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _alertsTab = 2;

  late final DeviceStore _store;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _store = context.read<DeviceStore>()..addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _select(int index) {
    setState(() => _index = index);
    if (index == _alertsTab) {
      _store.markAlertsRead();
      // 告警已经在列表里了，不用再弹提示
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  void _onStoreChanged() {
    if (!mounted) return;
    // 停留在告警页期间收到的告警直接算已读
    if (_index == _alertsTab) _store.markAlertsRead();

    final messenger = ScaffoldMessenger.of(context);
    final error = _store.takeError();
    if (error != null) messenger.showLatest(SnackBar(content: Text(error)));

    final alert = _store.takeIncomingAlert();
    if (alert != null && _index != _alertsTab) {
      final scheme = Theme.of(context).colorScheme;
      final critical = alert.level == AlertLevel.critical;
      messenger.showLatest(
        SnackBar(
          backgroundColor: critical ? scheme.error : null,
          duration: Duration(seconds: critical ? 10 : 4),
          content: Row(
            children: [
              Icon(alert.level.icon, color: critical ? scheme.onError : Colors.orange),
              const SizedBox(width: 8),
              Expanded(child: Text(alert.title)),
            ],
          ),
          action: SnackBarAction(
            label: '查看',
            textColor: critical ? scheme.onError : null,
            onPressed: () => _select(_alertsTab),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.select<DeviceStore, int>((s) => s.unreadAlerts);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(onOpenAlerts: () => _select(_alertsTab), onOpenScenes: () => _select(1)),
          const ScenesScreen(),
          const AlertsScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          const NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: '场景',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: const Icon(Icons.notifications_rounded),
            label: '告警',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
