import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../state/device_store.dart';
import 'device_control_sheet.dart';
import 'platform_badge.dart';

class DeviceCard extends StatelessWidget {
  const DeviceCard({super.key, required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final store = context.read<DeviceStore>();
    final pending = context.select<DeviceStore, bool>((s) => s.isPending(device.id));
    final scheme = Theme.of(context).colorScheme;
    final active = device.online && device.isOn;

    return Opacity(
      opacity: device.online ? 1 : 0.5,
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: active ? scheme.primaryContainer : null,
        child: InkWell(
          onTap: () => DeviceControlSheet.show(context, device.id),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(device.type.icon, color: active ? scheme.primary : scheme.outline),
                    const Spacer(),
                    if (pending)
                      const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    else if (device.hasPowerSwitch)
                      Switch(
                        value: device.isOn,
                        onChanged: device.online ? (on) => store.setPower(device, on) : null,
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(device.summary, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6),
                Row(
                  children: [
                    PlatformBadge(device.platform),
                    if (device.room != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          device.room!,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
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
