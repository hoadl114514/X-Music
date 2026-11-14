import 'package:flutter/foundation.dart';

/// 电脑平台（Windows / macOS / Linux），包括在电脑浏览器里打开的网页版。
/// 决定是否可以用宽屏布局。
bool get isDesktopPlatform => switch (defaultTargetPlatform) {
  TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => true,
  _ => false,
};

/// 原生电脑客户端（不是网页版）。托盘、全局快捷键这类原生能力只在这里启用。
bool get isNativeDesktop => !kIsWeb && isDesktopPlatform;
