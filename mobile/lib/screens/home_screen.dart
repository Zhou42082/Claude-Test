import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../state/device_store.dart';
import '../theme/app_theme.dart';
import '../widgets/air_quality_view.dart';
import '../widgets/device_card.dart';
import '../widgets/scene_tile.dart';
import 'demo_screen.dart';
import 'settings_screen.dart';

/// 首页：问候、家庭概览、常用场景、按房间浏览设备
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpenAlerts, this.onOpenScenes});

  final VoidCallback? onOpenAlerts;
  final VoidCallback? onOpenScenes;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// null 表示全部房间
  String? _room;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeviceStore>();
    final rooms = store.rooms;
    if (_room != null && !rooms.contains(_room)) _room = null;
    final devices = store.devicesIn(_room);
    final scenes = store.scenesIn(null);

    return RefreshIndicator(
      onRefresh: () async => store.reconnect(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: PageHeader(
                title: greeting(DateTime.now()),
                subtitle: '我的家 · ${formatDate(DateTime.now())}',
                trailing: store.demoScenarios.isEmpty
                    ? null
                    : IconButton.filledTonal(
                        tooltip: '演示工具',
                        icon: const Icon(Icons.science_outlined),
                        onPressed: () =>
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DemoScreen())),
                      ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _StatusPills(status: store.status, demo: store.isDemo),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: OverviewCard(summary: store.summary, onOpenAlerts: widget.onOpenAlerts),
            ),
          ),
          if (scenes.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionTitle(
                title: '常用场景',
                action: widget.onOpenScenes == null
                    ? null
                    : TextButton(onPressed: widget.onOpenScenes, child: const Text('全部')),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 96,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: scenes.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => SizedBox(width: 92, child: SceneTile(scene: scenes[i])),
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: _SectionTitle(
              title: '设备',
              action: _PlatformFilterButton(store: store),
            ),
          ),
          SliverToBoxAdapter(
            child: _RoomSelector(
              rooms: rooms,
              selected: _room,
              countIn: (room) => store.devicesIn(room).length,
              onSelected: (room) => setState(() => _room = room),
            ),
          ),
          if (store.platformFilter != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    label: Text('只看 ${store.platformFilter!.label}'),
                    onDeleted: () => store.platformFilter = null,
                  ),
                ),
              ),
            ),
          if (devices.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                icon: Icons.devices_other_rounded,
                text: store.status == ConnectionStatus.connected ? '这里还没有设备' : '正在获取设备…',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.12,
                ),
                itemCount: devices.length,
                itemBuilder: (_, i) => DeviceCard(device: devices[i]),
              ),
            ),
        ],
      ),
    );
  }
}

String greeting(DateTime now) => switch (now.hour) {
  < 5 => '夜深了',
  < 11 => '早上好',
  < 13 => '中午好',
  < 18 => '下午好',
  _ => '晚上好',
};

String formatDate(DateTime d) {
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  return '${d.month}月${d.day}日 星期${weekdays[d.weekday - 1]}';
}

/// 家庭概览卡片：室内环境、设备在线情况、需要注意的事
class OverviewCard extends StatelessWidget {
  const OverviewCard({super.key, required this.summary, this.onOpenAlerts});

  final HomeSummary summary;
  final VoidCallback? onOpenAlerts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const onCard = Colors.white;
    final muted = Colors.white.withValues(alpha: 0.78);
    final temperature = summary.temperature;
    final pm25 = summary.pm25;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF1F5547), Color(0xFF2C6E5C)]
              : const [Color(0xFF2E7D6B), Color(0xFF5BA88F)],
        ),
        boxShadow: [
          if (!dark)
            BoxShadow(
              color: AppTheme.seed.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      temperature == null
                          ? '${summary.online}/${summary.total}'
                          : '${temperature.toStringAsFixed(1)}°',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: onCard,
                        fontWeight: FontWeight.w300,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(temperature == null ? '设备在线' : '室内温度', style: TextStyle(color: muted)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (summary.humidity != null)
                    _Stat(icon: Icons.water_drop_outlined, text: '湿度 ${summary.humidity!.round()}%'),
                  if (pm25 != null)
                    _Stat(
                      icon: Icons.air_rounded,
                      text: 'PM2.5 ${pm25.round()} · ${AirQualityView.level(pm25).$1}',
                    ),
                  _Stat(icon: Icons.bolt_rounded, text: '${summary.active} 台运行中'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.wifi_rounded, size: 16, color: muted),
              const SizedBox(width: 6),
              Text('${summary.online}/${summary.total} 台在线', style: TextStyle(color: muted)),
              const Spacer(),
              _AttentionPill(summary: summary, onTap: onOpenAlerts),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _AttentionPill extends StatelessWidget {
  const _AttentionPill({required this.summary, this.onTap});

  final HomeSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final offline = summary.total - summary.online;
    final (IconData icon, String text, Color color) = switch (summary) {
      HomeSummary(alarms: > 0) => (Icons.warning_rounded, '${summary.alarms} 台设备报警', const Color(0xFFFFD6D1)),
      HomeSummary(urgentAlerts: > 0) => (
        Icons.notifications_active_rounded,
        '${summary.urgentAlerts} 条告警待查看',
        const Color(0xFFFFE7B8),
      ),
      _ when offline > 0 => (Icons.cloud_off_rounded, '$offline 台离线', Colors.white.withValues(alpha: 0.9)),
      _ => (Icons.check_circle_rounded, '一切正常', Colors.white.withValues(alpha: 0.9)),
    };
    final urgent = summary.alarms > 0 || summary.urgentAlerts > 0;
    return Material(
      color: urgent ? Colors.black.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: urgent ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                text,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPills extends StatelessWidget {
  const _StatusPills({required this.status, required this.demo});

  final ConnectionStatus status;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pills = <Widget>[
      if (status != ConnectionStatus.connected)
        _Pill(
          icon: status == ConnectionStatus.connecting ? null : Icons.cloud_off_rounded,
          text: status == ConnectionStatus.connecting ? '正在连接网关…' : '与网关的连接已断开，正在自动重连',
          background: scheme.errorContainer,
          foreground: scheme.onErrorContainer,
          action: status == ConnectionStatus.connecting
              ? null
              : ('重试', context.read<DeviceStore>().reconnect),
        ),
      if (demo)
        _Pill(
          icon: Icons.science_outlined,
          text: '演示模式 · 设备和数据都是模拟的',
          background: scheme.tertiaryContainer,
          foreground: scheme.onTertiaryContainer,
          action: (
            '连接网关',
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ),
    ];
    if (pills.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        children: [for (final p in pills) Padding(padding: const EdgeInsets.only(bottom: 6), child: p)],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.background,
    required this.foreground,
    this.icon,
    this.action,
  });

  final IconData? icon;
  final String text;
  final Color background;
  final Color foreground;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          if (icon == null)
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
            )
          else
            Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: foreground)),
          ),
          if (action != null)
            TextButton(
              onPressed: action!.$2,
              style: TextButton.styleFrom(foregroundColor: foreground, visualDensity: VisualDensity.compact),
              child: Text(action!.$1),
            )
          else
            const SizedBox(height: 36),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          ?action,
        ],
      ),
    );
  }
}

class _RoomSelector extends StatelessWidget {
  const _RoomSelector({
    required this.rooms,
    required this.selected,
    required this.countIn,
    required this.onSelected,
  });

  final List<String> rooms;
  final String? selected;
  final int Function(String?) countIn;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        children: [
          for (final room in <String?>[null, ...rooms])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${room ?? '全部'} ${countIn(room)}'),
                selected: selected == room,
                onSelected: (_) => onSelected(room),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlatformFilterButton extends StatelessWidget {
  const _PlatformFilterButton({required this.store});

  final DeviceStore store;

  @override
  Widget build(BuildContext context) {
    final platforms = store.platforms;
    if (platforms.length < 2) return const SizedBox.shrink();
    return TextButton.icon(
      icon: const Icon(Icons.tune_rounded, size: 18),
      label: Text(store.platformFilter?.label ?? '全部平台'),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('按平台筛选', style: Theme.of(sheetContext).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in <DevicePlatform?>[null, ...platforms])
                      ChoiceChip(
                        label: Text(p?.label ?? '全部平台'),
                        selected: store.platformFilter == p,
                        onSelected: (_) {
                          store.platformFilter = p;
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: color.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text(text, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}
