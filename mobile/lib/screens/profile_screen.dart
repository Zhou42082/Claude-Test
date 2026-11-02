import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../state/device_store.dart';
import '../state/settings_store.dart';
import '../theme/app_theme.dart';
import '../widgets/platform_badge.dart';
import 'demo_screen.dart';
import 'settings_screen.dart';

/// 我的：网关连接、演示工具、已接入的平台
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeviceStore>();
    final config = context.select<SettingsStore, String>((s) => s.config.baseUrl);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (statusText, statusColor) = switch (store.status) {
      ConnectionStatus.connected => ('已连接', const Color(0xFF3CBF8A)),
      ConnectionStatus.connecting => ('连接中', const Color(0xFFF2A93B)),
      ConnectionStatus.disconnected => ('已断开', scheme.error),
    };
    final counts = <DevicePlatform, int>{};
    for (final d in store.devicesIn(null)) {
      counts[d.platform] = (counts[d.platform] ?? 0) + 1;
    }

    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SafeArea(bottom: false, child: PageHeader(title: '我的')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconBubble(
                    icon: store.isDemo ? Icons.science_rounded : Icons.router_rounded,
                    color: AppTheme.seed,
                    size: 52,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(store.isDemo ? '演示模式' : '家庭网关', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          store.isDemo ? '设备和数据由 App 模拟' : config,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 8, color: statusColor),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _MenuTile(
                  icon: Icons.settings_rounded,
                  color: const Color(0xFF5C8DF6),
                  title: '网关设置',
                  subtitle: store.isDemo ? '连接真实网关' : '地址与访问令牌',
                  onTap: () => push(const SettingsScreen()),
                ),
                if (store.demoScenarios.isNotEmpty) ...[
                  const Divider(indent: 68),
                  _MenuTile(
                    icon: Icons.science_rounded,
                    color: const Color(0xFFF08C4A),
                    title: '演示工具',
                    subtitle: '模拟漏水、门铃、门锁卡住等事件',
                    onTap: () => push(const DemoScreen()),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (counts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('已接入的平台', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final MapEntry(key: platform, value: count) in counts.entries)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PlatformBadge(platform),
                              const SizedBox(width: 4),
                              Text('$count 台', style: theme.textTheme.bodySmall),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '智能家居 · 统一控制小米、华为、涂鸦、乐橙、德施曼等平台',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: IconBubble(icon: icon, color: color, size: 38),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
