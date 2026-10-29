import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../state/device_store.dart';
import 'air_quality_view.dart';
import 'camera_snapshot_view.dart';
import 'lock_controls.dart';
import 'platform_badge.dart';

/// 设备详情 / 控制面板。根据设备的 capabilities 动态展示控件。
class DeviceControlSheet extends StatelessWidget {
  const DeviceControlSheet({super.key, required this.deviceId});

  final String deviceId;

  static Future<void> show(BuildContext context, String deviceId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DeviceControlSheet(deviceId: deviceId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final device = context.select<DeviceStore, Device?>((s) => s.device(deviceId));
    if (device == null) {
      return const SizedBox(height: 160, child: Center(child: Text('设备已被移除')));
    }
    final store = context.read<DeviceStore>();
    final theme = Theme.of(context);
    final enabled = device.online;

    void send(String action, [Map<String, Object?> params = const {}]) => store.send(device, action, params);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(device.type.icon, size: 32, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device.name, style: theme.textTheme.titleLarge),
                      Row(
                        children: [
                          PlatformBadge(device.platform),
                          const SizedBox(width: 6),
                          Text(
                            [device.room ?? '未分配房间', if (!device.online) '离线'].join(' · '),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (device.type == DeviceType.sensor || device.type == DeviceType.binarySensor)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(device.summary, style: theme.textTheme.displaySmall),
                ),
              ),
            if (device.type == DeviceType.lock) LockControls(device: device),
            if (device.type == DeviceType.camera) CameraSnapshotView(device: device),
            if (device.type == DeviceType.airPurifier) AirQualityView(device: device),
            if (device.hasPowerSwitch)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('电源'),
                value: device.isOn,
                onChanged: enabled ? (on) => store.setPower(device, on) : null,
              ),
            if (device.can(DeviceAction.setBrightness))
              _SliderControl(
                label: '亮度',
                unit: '%',
                value: (device.brightness ?? 0).toDouble(),
                min: 1,
                max: 100,
                enabled: enabled,
                onCommit: (v) => send(DeviceAction.setBrightness, {'brightness': v.round()}),
              ),
            if (device.can(DeviceAction.setColorTemp))
              _SliderControl(
                label: '色温',
                unit: 'K',
                value: (device.colorTempKelvin ?? 4000).toDouble(),
                min: (device.state['min_color_temp_kelvin'] as num? ?? 2700).toDouble(),
                max: (device.state['max_color_temp_kelvin'] as num? ?? 6500).toDouble(),
                enabled: enabled,
                onCommit: (v) => send(DeviceAction.setColorTemp, {'color_temp_kelvin': v.round()}),
              ),
            if (device.type == DeviceType.climate) ..._climateControls(context, device, send),
            if (device.can(DeviceAction.setFanSpeed))
              _SliderControl(
                label: '风速',
                unit: '%',
                value: (device.fanPercentage ?? 0).toDouble(),
                min: 0,
                max: 100,
                enabled: enabled,
                onCommit: (v) => send(DeviceAction.setFanSpeed, {'percentage': v.round()}),
              ),
            if (device.can(DeviceAction.setPresetMode)) ...[
              const Text('模式'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final mode in device.presetModes)
                    ChoiceChip(
                      label: Text(presetModeLabel(mode)),
                      selected: device.presetMode == mode,
                      onSelected: enabled
                          ? (_) => send(DeviceAction.setPresetMode, {'preset_mode': mode})
                          : null,
                    ),
                ],
              ),
            ],
            if (device.type == DeviceType.cover) ..._coverControls(device, send),
          ],
        ),
      ),
    );
  }

  List<Widget> _climateControls(
    BuildContext context,
    Device device,
    void Function(String, [Map<String, Object?>]) send,
  ) {
    final theme = Theme.of(context);
    final target = device.targetTemperature;
    final enabled = device.online;
    return [
      if (device.currentTemperature != null)
        Text('室内 ${device.currentTemperature!.toStringAsFixed(1)}°C', style: theme.textTheme.bodyMedium),
      if (device.can(DeviceAction.setTemperature) && target != null)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              icon: const Icon(Icons.remove),
              onPressed: enabled && target > 16
                  ? () => send(DeviceAction.setTemperature, {'temperature': target - 1})
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('${target.toStringAsFixed(0)}°C', style: theme.textTheme.displaySmall),
            ),
            IconButton.filledTonal(
              icon: const Icon(Icons.add),
              onPressed: enabled && target < 30
                  ? () => send(DeviceAction.setTemperature, {'temperature': target + 1})
                  : null,
            ),
          ],
        ),
      if (device.can(DeviceAction.setHvacMode)) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final mode in device.hvacModes)
              ChoiceChip(
                label: Text(hvacModeLabel(mode)),
                selected: device.hvacMode == mode,
                onSelected: enabled ? (_) => send(DeviceAction.setHvacMode, {'hvac_mode': mode}) : null,
              ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _coverControls(Device device, void Function(String, [Map<String, Object?>]) send) {
    final enabled = device.online;
    return [
      if (device.can(DeviceAction.setPosition))
        _SliderControl(
          label: '开合度',
          unit: '%',
          value: (device.position ?? 0).toDouble(),
          min: 0,
          max: 100,
          enabled: enabled,
          onCommit: (v) => send(DeviceAction.setPosition, {'position': v.round()}),
        ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          FilledButton.tonalIcon(
            onPressed: enabled ? () => send(DeviceAction.open) : null,
            icon: const Icon(Icons.unfold_more),
            label: const Text('打开'),
          ),
          if (device.can(DeviceAction.stop))
            FilledButton.tonalIcon(
              onPressed: enabled ? () => send(DeviceAction.stop) : null,
              icon: const Icon(Icons.pause),
              label: const Text('暂停'),
            ),
          FilledButton.tonalIcon(
            onPressed: enabled ? () => send(DeviceAction.close) : null,
            icon: const Icon(Icons.unfold_less),
            label: const Text('关闭'),
          ),
        ],
      ),
    ];
  }
}

/// 拖动过程中只更新本地值，松手后才下发命令，避免频繁请求。
class _SliderControl extends StatefulWidget {
  const _SliderControl({
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onCommit,
  });

  final String label;
  final String unit;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onCommit;

  @override
  State<_SliderControl> createState() => _SliderControlState();
}

class _SliderControlState extends State<_SliderControl> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final value = (_dragValue ?? widget.value).clamp(widget.min, widget.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Text(widget.label), const Spacer(), Text('${value.round()}${widget.unit}')]),
        Slider(
          value: value,
          min: widget.min,
          max: widget.max,
          onChanged: widget.enabled ? (v) => setState(() => _dragValue = v) : null,
          onChangeEnd: (v) {
            setState(() => _dragValue = null);
            widget.onCommit(v);
          },
        ),
      ],
    );
  }
}
