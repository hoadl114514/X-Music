import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import '../shell/app_shell.dart';
import '../state/account_controller.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'app_info.dart';
import 'services.dart';

class NeteaseClientApp extends StatefulWidget {
  const NeteaseClientApp({super.key, required this.services});

  final AppServices services;

  @override
  State<NeteaseClientApp> createState() => _NeteaseClientAppState();
}

class _NeteaseClientAppState extends State<NeteaseClientApp> {
  @override
  void initState() {
    super.initState();
    widget.services.account.restore();
  }

  @override
  void dispose() {
    widget.services.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    return AppScope(
      services: s,
      child: AccountScope(
        controller: s.account,
        child: PlayerScope(
          controller: s.player,
          child: PlayerTickScope(
            controller: s.player,
            child: DynamicColorBuilder(
              builder: (lightDynamic, darkDynamic) => ListenableBuilder(
                listenable: s.settings,
                builder: (context, _) {
                  final settings = s.settings;
                  // 动态取色：用系统壁纸色的主色做种子，重新生成完整的 M3 配色（各级 surface 齐全）。
                  AppScope._dynamicSupported = lightDynamic != null;
                  final useDynamic = settings.dynamicColor && lightDynamic != null;
                  final lightSeed = useDynamic ? lightDynamic.primary : settings.seedColor;
                  final darkSeed = useDynamic
                      ? (darkDynamic ?? lightDynamic).primary
                      : settings.seedColor;
                  return MaterialApp(
                    title: AppInfo.name,
                    debugShowCheckedModeBanner: false,
                    theme: AppTheme.fromSeed(lightSeed, Brightness.light),
                    darkTheme: AppTheme.fromSeed(darkSeed, Brightness.dark),
                    themeMode: settings.themeMode.mode,
                    scaffoldMessengerKey: AppScope.messengerKey,
                    home: const AppShell(),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 提供 [AppServices]，以及全局 SnackBar。
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.services;

  /// 在任意位置弹一条提示（包括播放页这种盖在主框架上面的路由）。
  static void toast(String message) {
    final m = messengerKey.currentState;
    if (m == null) return;
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  /// 系统是否提供动态取色（Android 12 及以上）。设置页据此显示开关。
  static bool dynamicColorSupported(BuildContext context) => _dynamicSupported;
  static bool _dynamicSupported = false;

  @override
  bool updateShouldNotify(AppScope old) => old.services != services;
}
