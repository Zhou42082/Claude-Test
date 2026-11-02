import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/gateway_client.dart';
import '../state/device_store.dart';
import '../theme/app_theme.dart';
import '../widgets/snack_bar_ext.dart';

/// 演示工具：网关运行在演示模式（GATEWAY_ADAPTERS=mock）时，模拟漏水、门铃等事件，
/// 用来在没有真实设备的情况下测试告警和界面。
class DemoScreen extends StatelessWidget {
  const DemoScreen({super.key});

  static const _styles = <String, (IconData, Color)>{
    'leak': (Icons.water_drop_rounded, Color(0xFF3D9BE9)),
    'smoke': (Icons.local_fire_department_rounded, Color(0xFFE5533D)),
    'doorbell': (Icons.doorbell_rounded, Color(0xFFE8668C)),
    'motion': (Icons.directions_walk_rounded, Color(0xFFF2A93B)),
    'lock_jam': (Icons.lock_rounded, Color(0xFF8B6CEF)),
    'low_battery': (Icons.battery_alert_rounded, Color(0xFFFF8A5B)),
    'filter_low': (Icons.air_rounded, Color(0xFF3CBF8A)),
    'camera_offline': (Icons.videocam_off_rounded, Color(0xFF7E8CA0)),
    'reset': (Icons.restart_alt_rounded, AppTheme.seed),
  };

  Future<void> _run(BuildContext context, DemoScenario scenario) async {
    final messenger = ScaffoldMessenger.of(context);
    if (await context.read<DeviceStore>().runDemo(scenario)) {
      messenger.showLatest(
        SnackBar(content: Text('已模拟：${scenario.name}'), duration: const Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scenarios = context.select<DeviceStore, List<DemoScenario>>((s) => s.demoScenarios);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('演示工具')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
            child: Text(
              '点击下面的事件，模拟设备状态变化，然后回到首页、告警页和设备面板看效果。',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, s) in scenarios.indexed) ...[
                  if (i > 0) const Divider(indent: 68),
                  Builder(
                    builder: (context) {
                      final (icon, color) =
                          _styles[s.id.split(':').last] ?? (Icons.science_rounded, AppTheme.seed);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: IconBubble(icon: icon, color: color, size: 38),
                        title: Text(s.name, style: theme.textTheme.titleSmall),
                        trailing: const Icon(Icons.play_arrow_rounded),
                        onTap: () => _run(context, s),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
