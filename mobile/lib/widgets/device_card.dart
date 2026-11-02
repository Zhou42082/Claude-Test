import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/alert.dart';
import '../models/device.dart';
import '../state/device_store.dart';
import '../theme/app_theme.dart';
import 'device_control_sheet.dart';
import 'platform_badge.dart';

class DeviceCard extends StatelessWidget {
  const DeviceCard({super.key, required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final store = context.read<DeviceStore>();
    final pending = context.select<DeviceStore, bool>((s) => s.isPending(device.id));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = device.type.accent;
    final alarm = device.online && device.isAlarm;
    final active = device.online && device.isOn;

    final background = alarm
        ? scheme.errorContainer
        : active
        ? Color.alphaBlend(device.type.activeTint(theme.brightness), scheme.surface)
        : scheme.surface;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: device.online ? 1 : 0.55,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            if (theme.brightness == Brightness.light)
              BoxShadow(
                color: const Color(0xFF7A5C3C).withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => DeviceControlSheet.show(context, device.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconBubble(
                        icon: alarm ? Icons.warning_amber_rounded : device.type.icon,
                        color: alarm ? AlertLevel.critical.color(scheme) : accent,
                        filled: active || alarm,
                      ),
                      const Spacer(),
                      if (pending)
                        const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (device.hasPowerSwitch)
                        Transform.scale(
                          scale: 0.85,
                          child: Switch(
                            value: device.isOn,
                            activeTrackColor: accent,
                            activeThumbColor: Colors.white,
                            trackOutlineColor: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.selected) ? Colors.transparent : null,
                            ),
                            onChanged: device.online ? (on) => store.setPower(device, on) : null,
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    device.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    device.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: alarm ? scheme.error : scheme.onSurfaceVariant,
                      fontWeight: alarm ? FontWeight.w700 : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      PlatformBadge(device.platform),
                      if (device.room != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            device.room!,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
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
      ),
    );
  }
}
