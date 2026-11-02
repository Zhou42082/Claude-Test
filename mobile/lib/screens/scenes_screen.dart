import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../state/device_store.dart';
import '../theme/app_theme.dart';
import '../widgets/scene_tile.dart';

/// 场景页。场景在 Home Assistant 中配置（scene / script），App 只负责一键执行。
class ScenesScreen extends StatelessWidget {
  const ScenesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scenes = context.select<DeviceStore, List<Device>>((s) => s.scenesIn(null));
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: PageHeader(title: '场景', subtitle: '一键控制多个设备'),
          ),
        ),
        if (scenes.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text(
                    '还没有场景。在 Home Assistant 里创建场景或脚本后，会自动出现在这里。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.25,
              ),
              itemCount: scenes.length,
              itemBuilder: (_, i) => SceneTile(scene: scenes[i], compact: false),
            ),
          ),
      ],
    );
  }
}
