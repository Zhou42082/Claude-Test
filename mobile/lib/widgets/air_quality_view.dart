import 'package:flutter/material.dart';

import '../models/device.dart';

/// 净化器的 PM2.5 与滤芯寿命。分级参照 GB 3095-2012 的 PM2.5 24 小时浓度限值。
class AirQualityView extends StatelessWidget {
  const AirQualityView({super.key, required this.device});

  final Device device;

  static (String, Color) level(double pm25) => switch (pm25) {
    <= 35 => ('优', Colors.green),
    <= 75 => ('良', Colors.lightGreen),
    <= 115 => ('轻度污染', Colors.orange),
    <= 150 => ('中度污染', Colors.deepOrange),
    <= 250 => ('重度污染', Colors.red),
    _ => ('严重污染', Colors.purple),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pm25 = device.pm25;
    final filter = device.filterLife;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pm25 != null)
          Builder(
            builder: (context) {
              final (label, color) = level(pm25);
              return Column(
                children: [
                  Text('PM2.5', style: theme.textTheme.labelMedium),
                  Text('${pm25.round()}', style: theme.textTheme.displayMedium?.copyWith(color: color)),
                  Text('$label · µg/m³', style: theme.textTheme.bodySmall?.copyWith(color: color)),
                ],
              );
            },
          ),
        if (filter != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('滤芯剩余'),
              const Spacer(),
              Text('$filter%', style: TextStyle(color: filter < 10 ? theme.colorScheme.error : null)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: filter / 100, color: filter < 10 ? theme.colorScheme.error : null),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}
