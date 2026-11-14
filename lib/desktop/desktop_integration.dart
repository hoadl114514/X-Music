import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../app/app_info.dart';
import '../state/player_controller.dart';

/// 电脑端的窗口、系统托盘和全局快捷键。
///
/// - 关闭窗口时隐藏到托盘，继续播放；托盘菜单里「退出」才真正退出。
/// - 托盘菜单：显示窗口、播放 / 暂停、上一首、下一首、退出。
/// - 全局快捷键（应用在后台也生效）：
///   Windows：Ctrl+Alt+空格 / ← / → / ↑ / ↓；
///   macOS：⌘⌥+空格 / ← / → / ↑ / ↓。
///   分别是播放暂停、上一首、下一首、音量加、音量减。
///
/// 只在原生电脑客户端里创建。某一项初始化失败时跳过它，不影响其他功能。
class DesktopIntegration with WindowListener, TrayListener {
  DesktopIntegration._(this._player);

  final PlayerController _player;

  /// 窗口最小尺寸。再窄就放不下手机布局了。
  static const minSize = Size(400, 600);

  /// 音量快捷键每次调整的幅度。
  static const volumeStep = 0.1;

  /// 在 runApp 之前调用：配置窗口，准备好后再显示，避免启动时闪白。
  static Future<void> initWindow() async {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      title: AppInfo.name,
      minimumSize: minSize,
      size: Size(1280, 800),
      center: true,
      backgroundColor: Color(0xFF121212),
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  /// 接管关闭按钮，注册托盘和快捷键。
  static Future<DesktopIntegration> start(PlayerController player) async {
    final d = DesktopIntegration._(player);
    await d._guard('window', d._initWindow);
    await d._guard('tray', d._initTray);
    await d._guard('hotkeys', d._initHotkeys);
    player.addListener(d._onPlayerChanged);
    return d;
  }

  Future<void> _guard(String what, Future<void> Function() init) async {
    try {
      await init();
    } catch (e) {
      debugPrint('desktop $what init failed: $e');
    }
  }

  // ---------------- 窗口 ----------------

  Future<void> _initWindow() async {
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
  }

  /// 点关闭按钮：隐藏到托盘，不退出。
  @override
  void onWindowClose() {
    unawaited(windowManager.hide());
  }

  static Future<void> showWindow() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    await _guard('dispose', dispose);
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  // ---------------- 托盘 ----------------

  static const _show = 'show';
  static const _toggle = 'toggle';
  static const _previous = 'previous';
  static const _next = 'next';
  static const _quitKey = 'quit';

  bool? _menuPlaying;
  String? _menuSong;

  Future<void> _initTray() async {
    trayManager.addListener(this);
    if (Platform.isMacOS) {
      // 单色模板图标，系统会按菜单栏深浅色自动着色。
      await trayManager.setIcon('assets/tray/tray_mac.png', isTemplate: true);
    } else {
      await trayManager.setIcon('assets/tray/tray_windows.ico');
    }
    await _updateTray();
  }

  Future<void> _updateTray() async {
    final song = _player.current;
    final playing = _player.isPlaying;
    final label = song == null ? null : '${song.title} - ${song.artist}';
    if (playing == _menuPlaying && label == _menuSong) return;
    _menuPlaying = playing;
    _menuSong = label;
    // macOS 菜单栏的提示文字由图标自己显示，tooltip 只对 Windows 有效。
    if (!Platform.isMacOS) await trayManager.setToolTip(label ?? AppInfo.name);
    await trayManager.setContextMenu(
      Menu(
        items: [
          if (label != null) MenuItem(label: _ellipsis(label), disabled: true),
          if (label != null) MenuItem.separator(),
          MenuItem(key: _toggle, label: playing ? '暂停' : '播放'),
          MenuItem(key: _previous, label: '上一首'),
          MenuItem(key: _next, label: '下一首'),
          MenuItem.separator(),
          MenuItem(key: _show, label: '显示主窗口'),
          MenuItem(key: _quitKey, label: '退出 ${AppInfo.name}'),
        ],
      ),
    );
  }

  static String _ellipsis(String s) => s.length <= 32 ? s : '${s.substring(0, 31)}…';

  void _onPlayerChanged() => unawaited(_guard('tray update', _updateTray));

  /// 左键单击托盘图标：显示主窗口（Windows 习惯）。macOS 上单击弹菜单。
  @override
  void onTrayIconMouseDown() {
    if (Platform.isMacOS) {
      unawaited(trayManager.popUpContextMenu());
    } else {
      unawaited(showWindow());
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _show:
        unawaited(showWindow());
      case _toggle:
        unawaited(_player.toggle());
      case _previous:
        unawaited(_player.previous());
      case _next:
        unawaited(_player.next());
      case _quitKey:
        unawaited(_quit());
    }
  }

  // ---------------- 全局快捷键 ----------------

  Future<void> _initHotkeys() async {
    // 热重载后旧的注册还在，先清掉。
    await hotKeyManager.unregisterAll();
    final mods = Platform.isMacOS
        ? [HotKeyModifier.meta, HotKeyModifier.alt]
        : [HotKeyModifier.control, HotKeyModifier.alt];
    Future<void> bind(PhysicalKeyboardKey key, void Function() action) => hotKeyManager.register(
      HotKey(key: key, modifiers: mods),
      keyDownHandler: (_) => action(),
    );
    await bind(PhysicalKeyboardKey.space, () => unawaited(_player.toggle()));
    await bind(PhysicalKeyboardKey.arrowLeft, () => unawaited(_player.previous()));
    await bind(PhysicalKeyboardKey.arrowRight, () => unawaited(_player.next()));
    await bind(PhysicalKeyboardKey.arrowUp, () => _player.setVolume(_player.volume + volumeStep));
    await bind(PhysicalKeyboardKey.arrowDown, () => _player.setVolume(_player.volume - volumeStep));
  }

  Future<void> dispose() async {
    _player.removeListener(_onPlayerChanged);
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    await hotKeyManager.unregisterAll();
    await trayManager.destroy();
  }
}
