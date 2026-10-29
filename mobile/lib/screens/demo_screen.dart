import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/gateway_client.dart';
import '../state/device_store.dart';
import '../widgets/snack_bar_ext.dart';

/// 演示工具：网关运行在演示模式（GATEWAY_ADAPTERS=mock）时，模拟漏水、门铃等事件，
/// 用来在没有真实设备的情况下测试告警和界面。
class DemoScreen extends StatelessWidget {
  const DemoScreen({super.key});

  static const _icons = {
    'leak': Icons.water_drop_outlined,
    'smoke': Icons.local_fire_department_outlined,
    'doorbell': Icons.doorbell_outlined,
    'motion': Icons.directions_walk,
    'lock_jam': Icons.lock_outline,
    'low_battery': Icons.battery_alert,
    'filter_low': Icons.air,
    'camera_offline': Icons.videocam_off_outlined,
    'reset': Icons.restart_alt,
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
    return Scaffold(
      appBar: AppBar(title: const Text('演示工具')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('网关正在演示模式下运行。点击下面的事件，模拟设备状态变化，观察首页、告警和设备面板的反应。'),
          ),
          for (final s in scenarios)
            ListTile(
              leading: Icon(_icons[s.id.split(':').last] ?? Icons.science_outlined),
              title: Text(s.name),
              onTap: () => _run(context, s),
            ),
        ],
      ),
    );
  }
}
