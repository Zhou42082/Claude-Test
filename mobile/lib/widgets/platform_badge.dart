import 'package:flutter/material.dart';

import '../models/device.dart';

class PlatformBadge extends StatelessWidget {
  const PlatformBadge(this.platform, {super.key});

  final DevicePlatform platform;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: platform.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        platform.label,
        style: TextStyle(fontSize: 11, color: platform.color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
