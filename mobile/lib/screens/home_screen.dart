import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/alert.dart';
import '../models/device.dart';
import '../state/device_store.dart';
import '../widgets/snack_bar_ext.dart';
import '../widgets/device_card.dart';
import 'alerts_screen.dart';
import 'demo_screen.dart';
import 'settings_screen.dart';

const _allRooms = '全部';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final DeviceStore _store;

  @override
  void initState() {
    super.initState();
    _store = context.read<DeviceStore>()..addListener(_showMessages);
  }

  @override
  void dispose() {
    _store.removeListener(_showMessages);
    super.dispose();
  }

  void _showMessages() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final error = _store.takeError();
    if (error != null) messenger.showLatest(SnackBar(content: Text(error)));

    final alert = _store.takeIncomingAlert();
    if (alert != null) {
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
            onPressed: _openAlerts,
          ),
        ),
      );
    }
  }

  void _openAlerts() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AlertsScreen()));

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeviceStore>();
    final rooms = [_allRooms, ...store.rooms];

    return DefaultTabController(
      // 房间列表变化时重建 TabController
      key: ValueKey(rooms.join('|')),
      length: rooms.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('我的家'),
          actions: [
            if (store.demoScenarios.isNotEmpty)
              IconButton(
                tooltip: '演示工具',
                icon: const Icon(Icons.science_outlined),
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DemoScreen())),
              ),
            IconButton(
              tooltip: '告警',
              onPressed: _openAlerts,
              icon: Badge(
                isLabelVisible: store.unreadAlerts > 0,
                label: Text('${store.unreadAlerts}'),
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: '网关设置',
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final r in rooms) Tab(text: r)],
          ),
        ),
        body: Column(
          children: [
            _ConnectionBanner(status: store.status),
            _PlatformFilter(store: store),
            Expanded(
              child: TabBarView(
                children: [
                  for (final r in rooms)
                    _RoomView(
                      scenes: store.scenesIn(r == _allRooms ? null : r),
                      devices: store.devicesIn(r == _allRooms ? null : r),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == ConnectionStatus.connected) return const SizedBox.shrink();
    final connecting = status == ConnectionStatus.connecting;
    return MaterialBanner(
      leading: connecting
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.cloud_off),
      content: Text(connecting ? '正在连接网关…' : '与网关的连接已断开，正在自动重连'),
      actions: [
        TextButton(
          onPressed: connecting ? null : context.read<DeviceStore>().reconnect,
          child: const Text('立即重试'),
        ),
      ],
    );
  }
}

class _PlatformFilter extends StatelessWidget {
  const _PlatformFilter({required this.store});

  final DeviceStore store;

  @override
  Widget build(BuildContext context) {
    final platforms = store.platforms;
    if (platforms.length < 2) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final p in <DevicePlatform?>[null, ...platforms])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(p?.label ?? '全部平台'),
                selected: store.platformFilter == p,
                onSelected: (_) => store.platformFilter = p,
              ),
            ),
        ],
      ),
    );
  }
}

class _RoomView extends StatelessWidget {
  const _RoomView({required this.scenes, required this.devices});

  final List<Device> scenes;
  final List<Device> devices;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty && scenes.isEmpty) {
      return const Center(child: Text('暂无设备'));
    }
    return CustomScrollView(
      slivers: [
        if (scenes.isNotEmpty) SliverToBoxAdapter(child: _SceneBar(scenes: scenes)),
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.15,
            ),
            itemCount: devices.length,
            itemBuilder: (_, i) => DeviceCard(device: devices[i]),
          ),
        ),
      ],
    );
  }
}

/// 一键场景。场景在 Home Assistant 中配置（scene / script），App 只负责执行。
class _SceneBar extends StatelessWidget {
  const _SceneBar({required this.scenes});

  final List<Device> scenes;

  Future<void> _run(BuildContext context, Device scene) async {
    final messenger = ScaffoldMessenger.of(context);
    if (await context.read<DeviceStore>().send(scene, DeviceAction.activate)) {
      messenger.showLatest(SnackBar(content: Text('已执行「${scene.name}」')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeviceStore>();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          for (final scene in scenes)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: store.isPending(scene.id)
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(DeviceType.scene.icon, size: 18),
                label: Text(scene.name),
                onPressed: scene.online && !store.isPending(scene.id) ? () => _run(context, scene) : null,
              ),
            ),
        ],
      ),
    );
  }
}
