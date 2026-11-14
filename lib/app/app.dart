import 'package:flutter/material.dart';

import '../shell/app_shell.dart';
import '../shell/desktop_shell.dart';
import '../state/account_controller.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'app_info.dart';
import 'platform.dart';
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
          child: MaterialApp(
            title: AppInfo.name,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark(),
            scaffoldMessengerKey: AppScope.messengerKey,
            home: isDesktopPlatform ? const _ResponsiveShell() : const AppShell(),
          ),
        ),
      ),
    );
  }
}

/// 电脑上按窗口宽度选布局：够宽用三栏的电脑布局，窄了退回手机布局。
class _ResponsiveShell extends StatelessWidget {
  const _ResponsiveShell();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= desktopBreakpoint;
    return wide ? const DesktopShell() : const AppShell();
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

  @override
  bool updateShouldNotify(AppScope old) => old.services != services;
}
