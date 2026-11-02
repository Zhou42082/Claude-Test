import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/alert.dart';
import '../state/device_store.dart';
import '../theme/app_theme.dart';
import '../widgets/device_control_sheet.dart';

/// 告警列表，按天分组。告警由网关根据设备状态变化产生（漏水、烟雾、门锁、低电量等）。
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final alerts = context.select<DeviceStore, List<GatewayAlert>>((s) => s.alerts);
    final theme = Theme.of(context);
    final groups = <String, List<GatewayAlert>>{};
    for (final a in alerts) {
      groups.putIfAbsent(dayLabel(a.time), () => []).add(a);
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: PageHeader(title: '告警', subtitle: alerts.isEmpty ? null : '共 ${alerts.length} 条'),
          ),
        ),
        if (alerts.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconBubble(icon: Icons.verified_user_rounded, color: AppTheme.seed, size: 72),
                const SizedBox(height: 16),
                Text('暂无告警', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('漏水、烟雾、门锁异常等情况会第一时间通知你', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          )
        else
          for (final MapEntry(key: day, value: items) in groups.entries) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Text(
                  day,
                  style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _AlertTile(alert: items[i]),
              ),
            ),
          ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

String dayLabel(DateTime time, {DateTime? now}) {
  now ??= DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  return switch (today.difference(day).inDays) {
    0 => '今天',
    1 => '昨天',
    _ => '${time.month}月${time.day}日',
  };
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});

  final GatewayAlert alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = alert.level.color(scheme);
    final exists = context.read<DeviceStore>().device(alert.deviceId) != null;
    return Material(
      color: alert.level == AlertLevel.critical
          ? Color.alphaBlend(scheme.error.withValues(alpha: 0.08), scheme.surface)
          : scheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: exists ? () => DeviceControlSheet.show(context, alert.deviceId) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
          child: Row(
            children: [
              IconBubble(icon: alert.level.icon, color: color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alert.message, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      [if (alert.room != null) alert.room!, alert.deviceName].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text(
                formatAlertTime(alert.time),
                style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
