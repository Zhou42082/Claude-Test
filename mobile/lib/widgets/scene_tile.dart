import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../state/device_store.dart';
import '../theme/app_theme.dart';
import 'snack_bar_ext.dart';

/// 根据场景名称挑一个图标和颜色，没匹配到的用默认样式
(IconData, Color) sceneStyle(String name) {
  const styles = <(List<String>, IconData, Color)>[
    (['回家', '到家', 'home'], Icons.home_rounded, Color(0xFFF08C4A)),
    (['离家', '外出', 'away'], Icons.directions_walk_rounded, Color(0xFF5C8DF6)),
    (['睡眠', '晚安', '睡觉', 'sleep'], Icons.bedtime_rounded, Color(0xFF8B6CEF)),
    (['起床', '早安', 'morning'], Icons.wb_sunny_rounded, Color(0xFFF2A93B)),
    (['观影', '影院', '电影', 'movie'], Icons.movie_rounded, Color(0xFFE8668C)),
    (['用餐', '吃饭', 'dinner'], Icons.restaurant_rounded, Color(0xFF2BAE9F)),
  ];
  final lower = name.toLowerCase();
  for (final (keys, icon, color) in styles) {
    if (keys.any(lower.contains)) return (icon, color);
  }
  return (Icons.auto_awesome_rounded, DeviceType.scene.accent);
}

Future<void> runScene(BuildContext context, Device scene) async {
  final messenger = ScaffoldMessenger.of(context);
  if (await context.read<DeviceStore>().send(scene, DeviceAction.activate)) {
    messenger.showLatest(SnackBar(content: Text('已执行「${scene.name}」')));
  }
}

/// 场景按钮。compact 用于首页横排，否则用于场景页的大卡片。
class SceneTile extends StatelessWidget {
  const SceneTile({super.key, required this.scene, this.compact = true});

  final Device scene;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pending = context.select<DeviceStore, bool>((s) => s.isPending(scene.id));
    final theme = Theme.of(context);
    final (icon, color) = sceneStyle(scene.name);
    final enabled = scene.online && !pending;

    final iconWidget = pending
        ? SizedBox.square(
            dimension: compact ? 40 : 48,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : IconBubble(icon: icon, color: color, size: compact ? 40 : 48);

    return Material(
      color: compact
          ? theme.colorScheme.surface
          : Color.alphaBlend(color.withValues(alpha: 0.12), theme.colorScheme.surface),
      borderRadius: BorderRadius.circular(compact ? 20 : 24),
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        onTap: enabled ? () => runScene(context, scene) : null,
        child: Padding(
          padding: compact ? const EdgeInsets.fromLTRB(14, 12, 14, 12) : const EdgeInsets.all(18),
          child: compact
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    iconWidget,
                    const SizedBox(height: 8),
                    Text(
                      scene.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconWidget,
                    const Spacer(),
                    Text(scene.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      scene.room ?? '全屋',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
