import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 界面用到的颜色角色，按 Material 3 的配色方案生成。
///
/// 页面里用 `context.colors.xxx` 取色，跟着浅色 / 深色 / 动态取色一起变。
/// 字段名沿用旧版（textPrimary、accent……），每个字段对应一个 M3 颜色角色，见 [AppColors.fromScheme]。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.card,
    required this.cardHover,
    required this.border,
    required this.borderStrong,
    required this.outline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.negative,
  });

  /// 页面底色（M3 surface）。
  final Color background;

  /// 比底色高一级的面（surfaceContainerLow）。
  final Color surface;

  /// 抽屉、底部面板、搜索框（surfaceContainer）。
  final Color surfaceHigh;

  /// 卡片（surfaceContainerHigh）。
  final Color card;

  /// 卡片悬停 / 按下（surfaceContainerHighest）。
  final Color cardHover;

  /// 分隔线（outlineVariant）。
  final Color border;
  final Color borderStrong;
  final Color outline;

  /// 正文（onSurface）。
  final Color textPrimary;

  /// 次要文字（onSurfaceVariant）。
  final Color textSecondary;

  /// 更弱的文字：序号、时长、占位提示。
  final Color textMuted;

  /// 品牌色（primary）：播放中、选中、进度。
  final Color accent;
  final Color accentSoft;
  final Color onAccent;

  /// 红心、推荐理由、错误（M3 error）。
  final Color negative;

  /// 播放页的沉浸式暗色。播放页这一版不改，保留原来的颜色。
  static const immersive = AppColors(
    background: Color(0xFF121212),
    surface: Color(0xFF181818),
    surfaceHigh: Color(0xFF1F1F1F),
    card: Color(0xFF202020),
    cardHover: Color(0xFF2A2A2A),
    border: Color(0xFF2E2E2E),
    borderStrong: Color(0xFF4D4D4D),
    outline: Color(0xFF7C7C7C),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB3B3B3),
    textMuted: Color(0xFF7A7A7A),
    accent: AppTheme.sakura,
    accentSoft: Color(0xFFFFD3E6),
    onAccent: Color(0xFF1A0F14),
    negative: Color(0xFFF3727F),
  );

  factory AppColors.fromScheme(ColorScheme s) => AppColors(
    background: s.surface,
    surface: s.surfaceContainerLow,
    surfaceHigh: s.surfaceContainer,
    card: s.surfaceContainerHigh,
    cardHover: s.surfaceContainerHighest,
    border: s.outlineVariant,
    borderStrong: s.outline,
    outline: s.outline,
    textPrimary: s.onSurface,
    textSecondary: s.onSurfaceVariant,
    textMuted: Color.alphaBlend(s.onSurfaceVariant.withValues(alpha: 0.72), s.surface),
    accent: s.primary,
    accentSoft: s.primaryFixedDim,
    onAccent: s.onPrimary,
    negative: s.error,
  );

  /// 取当前主题的颜色。主题里没有这个扩展时（测试里直接建 MaterialApp）按配色方案现算。
  static AppColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppColors>() ?? AppColors.fromScheme(theme.colorScheme);
  }

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceHigh: l(surfaceHigh, other.surfaceHigh),
      card: l(card, other.card),
      cardHover: l(cardHover, other.cardHover),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      outline: l(outline, other.outline),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      accent: l(accent, other.accent),
      accentSoft: l(accentSoft, other.accentSoft),
      onAccent: l(onAccent, other.onAccent),
      negative: l(negative, other.negative),
    );
  }
}

extension AppColorsContext on BuildContext {
  /// 当前主题的颜色，见 [AppColors]。
  AppColors get colors => AppColors.of(this);

  /// 当前主题的 M3 配色方案。
  ColorScheme get scheme => Theme.of(this).colorScheme;
}

/// 圆角，对应 Material 3 的形状等级。
abstract final class AppRadius {
  /// 小标签（extra small）。
  static const double tag = 4;

  /// 列表封面、小卡片（small）。
  static const double small = 8;

  /// 卡片、封面（medium）。
  static const double card = 12;

  /// 大卡片、面板（large）。
  static const double panel = 16;

  /// 抽屉、底部面板、对话框（extra large）。
  static const double sheet = 28;
  static const double cover = 16;
  static const double pill = 999;
}

abstract final class AppShadows {
  static const medium = [BoxShadow(color: Color(0x4D000000), offset: Offset(0, 8), blurRadius: 8)];
  static const heavy = [BoxShadow(color: Color(0x80000000), offset: Offset(0, 8), blurRadius: 24)];
}

/// 主题模式。
enum AppThemeMode {
  system('跟随系统', ThemeMode.system),
  light('浅色', ThemeMode.light),
  dark('深色', ThemeMode.dark);

  const AppThemeMode(this.label, this.mode);

  final String label;
  final ThemeMode mode;

  static AppThemeMode byName(String? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => system);
}

abstract final class AppTheme {
  /// 樱花粉，默认的种子色。
  static const sakura = Color(0xFFF5A3C7);

  /// 设置里可选的种子色（关掉动态取色时用）。
  static const seeds = <(String, Color)>[
    ('樱花粉', sakura),
    ('珊瑚红', Color(0xFFE0574F)),
    ('琥珀橙', Color(0xFFE8A13A)),
    ('薄荷绿', Color(0xFF4CAF7D)),
    ('湖水青', Color(0xFF2FA3B5)),
    ('天空蓝', Color(0xFF4A7FD9)),
    ('薰衣草', Color(0xFF8B6FD6)),
  ];

  /// 由种子色生成的 M3 主题。
  static ThemeData fromSeed(Color seed, Brightness brightness) => build(
    ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    ),
  );

  /// Material 3 主题：颜色来自 [scheme]，字体用 M3 字号体系，形状用 M3 圆角等级。
  static ThemeData build(ColorScheme scheme) {
    final colors = AppColors.fromScheme(scheme);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );
    // M3 字号体系（Typography.material2021），中文标题加一点字重更醒目。
    final text = base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w500),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w500),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500),
    );
    const largeShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.panel)),
    );

    return base.copyWith(
      textTheme: text,
      extensions: [colors],
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 3,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerHighest,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyLarge?.copyWith(color: scheme.onSurface),
        subtitleTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 24),
        minVerticalPadding: 8,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 80,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.secondaryContainer,
        tileHeight: 56,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelLarge?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        scrimColor: scheme.scrim.withValues(alpha: 0.32),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        hintStyle: WidgetStatePropertyAll(text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
        constraints: const BoxConstraints(minHeight: 56),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.sheet)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.small)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.tag)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.small)),
        ),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        shape: largeShape,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(AppRadius.tag),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
        waitDuration: const Duration(milliseconds: 500),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.secondaryContainer,
        thumbColor: scheme.primary,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(AppRadius.pill),
        thumbColor: WidgetStatePropertyAll(scheme.onSurface.withValues(alpha: 0.24)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      // M3 页面转场：安卓用新的渐进式转场（新页从右侧滑入并淡入，旧页同步淡出）。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// 播放页用的沉浸式暗色主题，和改版前完全一样。
  static ThemeData immersive() {
    const c = AppColors.immersive;
    final scheme = ColorScheme.dark(
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.accentSoft,
      onSecondary: c.onAccent,
      surface: c.background,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surfaceHigh,
      surfaceContainerHigh: c.card,
      surfaceContainerHighest: c.cardHover,
      outline: c.outline,
      outlineVariant: c.border,
      error: c.negative,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    // 紧凑的字号体系：10–24 之间，靠字重而非字号拉开层级。
    final text = base.textTheme
        .copyWith(
          headlineMedium: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.2),
          titleLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          titleMedium: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3),
          titleSmall: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          bodyLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
          bodyMedium: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
          bodySmall: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
          labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          labelMedium: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          labelSmall: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
        )
        .apply(bodyColor: c.textPrimary, displayColor: c.textPrimary);

    return base.copyWith(
      textTheme: text,
      extensions: const [AppColors.immersive],
      iconTheme: IconThemeData(color: c.textSecondary, size: 20),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.cardHover,
          borderRadius: BorderRadius.circular(AppRadius.tag),
          boxShadow: AppShadows.heavy,
        ),
        textStyle: text.bodySmall,
        waitDuration: const Duration(milliseconds: 500),
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.surfaceHigh),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: c.accent,
        inactiveTrackColor: const Color(0x33FFFFFF),
        thumbColor: c.accentSoft,
        overlayColor: const Color(0x22F5A3C7),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(AppRadius.pill),
        thumbColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.18)),
      ),
    );
  }
}
