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
            child: MaterialApp(
              title: AppInfo.name,
              debugShowCheckedModeBanner: false,
              theme: AppTheme.dark(),
              scaffoldMessengerKey: AppScope.messengerKey,
              home: const AppShell(),
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

  @override
  bool updateShouldNotify(AppScope old) => old.services != services;
}
