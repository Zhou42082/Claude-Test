import 'package:flutter/material.dart';

import '../models/device.dart';

class PlatformBadge extends StatelessWidget {
  const PlatformBadge(this.platform, {super.key});

  final DevicePlatform platform;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: platform.color.withValues(alpha: dark ? 0.24 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        platform.label,
        style: TextStyle(
          fontSize: 11,
          height: 1.4,
          color: dark ? Color.lerp(platform.color, Colors.white, 0.35) : platform.color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
