import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../state/device_store.dart';

/// 门锁控制。开锁需要输入网关上配置的 PIN（GATEWAY_UNLOCK_PIN），PIN 只在网关校验。
class LockControls extends StatelessWidget {
  const LockControls({super.key, required this.device});

  final Device device;

  Future<void> _unlock(BuildContext context) async {
    final store = context.read<DeviceStore>();
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => _PinDialog(deviceName: device.name),
    );
    if (pin != null && pin.isNotEmpty) await store.send(device, DeviceAction.unlock, {'pin': pin});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.read<DeviceStore>();
    final pending = context.select<DeviceStore, bool>((s) => s.isPending(device.id));
    final enabled = device.online && !pending;
    final locked = device.isLocked;
    final alert = device.lockState == 'jammed' || !locked;

    return Column(
      children: [
        Icon(
          locked ? Icons.lock : Icons.lock_open,
          size: 64,
          color: alert ? theme.colorScheme.error : theme.colorScheme.primary,
        ),
        const SizedBox(height: 8),
        Text(lockStateLabel(device.lockState), style: theme.textTheme.titleLarge),
        if (device.battery != null) ...[
          const SizedBox(height: 4),
          Text('电量 ${device.battery}%', style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (device.can(DeviceAction.lock))
              FilledButton.tonalIcon(
                onPressed: enabled && !locked ? () => store.send(device, DeviceAction.lock) : null,
                icon: const Icon(Icons.lock),
                label: const Text('上锁'),
              ),
            if (device.can(DeviceAction.unlock))
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                onPressed: enabled && locked ? () => _unlock(context) : null,
                icon: const Icon(Icons.lock_open),
                label: const Text('远程开锁'),
              ),
          ],
        ),
      ],
    );
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.deviceName});

  final String deviceName;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('开锁「${widget.deviceName}」'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: '开锁 PIN'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('开锁')),
      ],
    );
  }
}
