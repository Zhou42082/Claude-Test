import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../state/device_store.dart';
import '../widgets/device_card.dart';
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
    _store = context.read<DeviceStore>()..addListener(_showError);
  }

  @override
  void dispose() {
    _store.removeListener(_showError);
    super.dispose();
  }

  void _showError() {
    final error = _store.takeError();
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

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
                  for (final r in rooms) _DeviceGrid(devices: store.devicesIn(r == _allRooms ? null : r)),
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

class _DeviceGrid extends StatelessWidget {
  const _DeviceGrid({required this.devices});

  final List<Device> devices;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return const Center(child: Text('暂无设备'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.15,
      ),
      itemCount: devices.length,
      itemBuilder: (_, i) => DeviceCard(device: devices[i]),
    );
  }
}
