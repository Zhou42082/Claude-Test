import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/alert.dart';
import '../state/device_store.dart';
import '../widgets/device_control_sheet.dart';

/// 告警列表。告警由网关根据设备状态变化产生（漏水、烟雾、门锁、低电量等）。
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late final DeviceStore _store;

  @override
  void initState() {
    super.initState();
    _store = context.read<DeviceStore>();
    // 停留在本页期间收到的新告警也视为已读
    WidgetsBinding.instance.addPostFrameCallback((_) => _store.markAlertsRead());
    _store.addListener(_store.markAlertsRead);
  }

  @override
  void dispose() {
    _store.removeListener(_store.markAlertsRead);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alerts = context.select<DeviceStore, List<GatewayAlert>>((s) => s.alerts);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('告警')),
      body: alerts.isEmpty
          ? const Center(child: Text('暂无告警'))
          : ListView.separated(
              itemCount: alerts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final alert = alerts[i];
                final color = alert.level.color(scheme);
                final exists = _store.device(alert.deviceId) != null;
                return ListTile(
                  leading: Icon(alert.level.icon, color: color),
                  title: Text(alert.message),
                  subtitle: Text([if (alert.room != null) alert.room!, alert.deviceName].join(' · ')),
                  trailing: Text(formatAlertTime(alert.time), style: Theme.of(context).textTheme.bodySmall),
                  onTap: exists ? () => DeviceControlSheet.show(context, alert.deviceId) : null,
                );
              },
            ),
    );
  }
}
