import 'package:flutter/material.dart';

/// 告警级别，与网关 AlertLevel 对应。
enum AlertLevel {
  info('提示', Icons.info_outline),
  warning('警告', Icons.warning_amber),
  critical('紧急', Icons.report);

  const AlertLevel(this.label, this.icon);

  final String label;
  final IconData icon;

  static AlertLevel parse(String? value) => values.firstWhere((l) => l.name == value, orElse: () => info);

  Color color(ColorScheme scheme) => switch (this) {
    info => scheme.primary,
    warning => Colors.orange,
    critical => scheme.error,
  };
}

class GatewayAlert {
  const GatewayAlert({
    required this.id,
    required this.time,
    required this.level,
    required this.deviceId,
    required this.deviceName,
    required this.message,
    this.room,
  });

  factory GatewayAlert.fromJson(Map<String, dynamic> json) => GatewayAlert(
    id: json['id'] as int,
    time: DateTime.parse(json['time'] as String).toLocal(),
    level: AlertLevel.parse(json['level'] as String?),
    deviceId: json['device_id'] as String,
    deviceName: json['device_name'] as String,
    room: json['room'] as String?,
    message: json['message'] as String,
  );

  final int id;
  final DateTime time;
  final AlertLevel level;
  final String deviceId;
  final String deviceName;
  final String? room;
  final String message;

  /// 「卧室 · 漏水传感器：检测到漏水」
  String get title => '${room != null ? '$room · ' : ''}$deviceName：$message';
}

/// 今天的只显示时间，否则带上日期
String formatAlertTime(DateTime time, {DateTime? now}) {
  now ??= DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(time.hour)}:${two(time.minute)}';
  final sameDay = time.year == now.year && time.month == now.month && time.day == now.day;
  return sameDay ? hm : '${time.month}月${time.day}日 $hm';
}
