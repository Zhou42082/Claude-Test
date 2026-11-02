import 'package:flutter/material.dart';

import '../models/device.dart';

/// 「温暖居家」主题：暖米色背景、大圆角白色卡片，每类设备有自己的柔和色彩。
abstract final class AppTheme {
  static const seed = Color(0xFF2E7D6B);

  static const _lightBackground = Color(0xFFF6F2EC);
  static const _darkBackground = Color(0xFF171513);

  static ThemeData light({String? fontFamily}) => _build(Brightness.light, fontFamily);
  static ThemeData dark({String? fontFamily}) => _build(Brightness.dark, fontFamily);

  static ThemeData _build(Brightness brightness, String? fontFamily) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness).copyWith(
      surface: isDark ? const Color(0xFF221F1C) : Colors.white,
      surfaceContainerLowest: isDark ? const Color(0xFF1C1A18) : const Color(0xFFFFFFFF),
      surfaceContainerLow: isDark ? const Color(0xFF26231F) : const Color(0xFFFBF8F4),
      surfaceContainer: isDark ? const Color(0xFF2B2824) : const Color(0xFFF2EEE8),
      surfaceContainerHigh: isDark ? const Color(0xFF332F2B) : const Color(0xFFECE7E0),
      surfaceContainerHighest: isDark ? const Color(0xFF3B3732) : const Color(0xFFE6E0D8),
      outlineVariant: isDark ? const Color(0xFF3F3A35) : const Color(0xFFE5DED5),
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: fontFamily);
    final text = base.textTheme;
    final radius16 = BorderRadius.circular(16);

    return base.copyWith(
      scaffoldBackgroundColor: isDark ? _darkBackground : _lightBackground,
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? _darkBackground : _lightBackground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: scheme.surface,
        selectedColor: scheme.primary,
        labelStyle: text.labelLarge,
        secondaryLabelStyle: text.labelLarge?.copyWith(color: scheme.onPrimary),
        checkmarkColor: scheme.onPrimary,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: radius16),
          textStyle: text.titleSmall,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: radius16),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: text.titleSmall,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        border: OutlineInputBorder(borderRadius: radius16, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: radius16, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius16,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? _darkBackground : _lightBackground,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      sliderTheme: base.sliderTheme.copyWith(trackHeight: 6),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    );
  }

  /// 设备控制面板使用以设备颜色为种子的配色，滑块、开关、选项都随设备变色
  static ThemeData forDevice(ThemeData theme, DeviceType type) {
    final scheme = ColorScheme.fromSeed(seedColor: type.accent, brightness: theme.brightness);
    final accent = type.accent;
    return theme.copyWith(
      // 滑块、开关、选中的选项直接用设备色，和首页卡片的颜色一致
      sliderTheme: theme.sliderTheme.copyWith(
        activeTrackColor: accent,
        thumbColor: accent,
        inactiveTrackColor: theme.colorScheme.surfaceContainerHigh,
        overlayColor: accent.withValues(alpha: 0.12),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accent : null,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.transparent : null,
        ),
      ),
      chipTheme: theme.chipTheme.copyWith(
        selectedColor: accent,
        secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(color: Colors.white),
      ),
      colorScheme: theme.colorScheme.copyWith(
        primary: scheme.primary,
        onPrimary: scheme.onPrimary,
        primaryContainer: scheme.primaryContainer,
        onPrimaryContainer: scheme.onPrimaryContainer,
        secondaryContainer: scheme.primaryContainer,
        onSecondaryContainer: scheme.onPrimaryContainer,
      ),
    );
  }
}

extension DeviceTypeStyle on DeviceType {
  /// 每类设备的强调色
  Color get accent => switch (this) {
    DeviceType.light => const Color(0xFFF2A93B),
    DeviceType.switchDevice => const Color(0xFFFF8A5B),
    DeviceType.climate => const Color(0xFF3D9BE9),
    DeviceType.cover => const Color(0xFF2BAE9F),
    DeviceType.fan => const Color(0xFF45B8D0),
    DeviceType.sensor => const Color(0xFF7E8CA0),
    DeviceType.binarySensor => const Color(0xFF6C7FD8),
    DeviceType.lock => const Color(0xFF8B6CEF),
    DeviceType.camera => const Color(0xFFE8668C),
    DeviceType.airPurifier => const Color(0xFF3CBF8A),
    DeviceType.scene => const Color(0xFFF08C4A),
    DeviceType.unknown => const Color(0xFF9E9E9E),
  };

  /// 卡片「开启」时的底色
  Color activeTint(Brightness brightness) =>
      accent.withValues(alpha: brightness == Brightness.dark ? 0.22 : 0.14);
}

/// 圆形图标底，设备卡片、控制面板、场景都用它
class IconBubble extends StatelessWidget {
  const IconBubble({super.key, required this.icon, required this.color, this.filled = true, this.size = 44});

  final IconData icon;
  final Color color;
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(color: filled ? color : scheme.surfaceContainer, shape: BoxShape.circle),
      child: Icon(icon, size: size * 0.5, color: filled ? Colors.white : scheme.onSurfaceVariant),
    );
  }
}

/// 页面顶部的大标题
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 控制面板里的分组卡片
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.title, this.trailing});

  final Widget child;
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(title!, style: theme.textTheme.titleSmall),
                  const Spacer(),
                  if (trailing != null)
                    DefaultTextStyle.merge(
                      style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
                      child: trailing!,
                    ),
                ],
              ),
            ),
          child,
        ],
      ),
    );
  }
}
