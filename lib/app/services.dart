import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import '../api/cookies.dart';
import '../api/netease_api.dart';
import '../audio/audio_cache.dart';
import '../audio/audio_engine.dart';
import '../audio/system_media.dart';
import '../audio/windows_media.dart';
import '../data/track_cache.dart';
import '../desktop/desktop_integration.dart';
import '../lyrics/lyric_service.dart';
import '../lyrics/qq_lyrics.dart';
import '../state/account_controller.dart';
import '../state/player_controller.dart';
import '../state/settings.dart';
import '../widgets/image_disk_cache.dart';
import 'app_info.dart';
import 'platform.dart';
import 'update_checker.dart';

/// 应用级的单例集合，在 main 里建好后整个往下传。
class AppServices {
  AppServices({
    required this.settings,
    required this.api,
    required this.account,
    required this.player,
    this.audioCache,
    PlaylistTracks? tracks,
    this.updates,
    this.desktop,
    this.windowsMedia,
  }) : tracks = tracks ?? PlaylistTracks(api);

  /// 正式环境：真实网络 + just_audio。
  static Future<AppServices> create() async {
    // 内存里多留些解码好的图（默认 100MB 只够二三十张大封面），切页面回来不用重新解码。
    PaintingBinding.instance.imageCache
      ..maximumSize = 2000
      ..maximumSizeBytes = 256 << 20;
    unawaited(ImageDiskCache.prune());
    final settings = await AppSettings.load();
    final api = NeteaseApi(cookies: parseCookie(settings.cookie));
    final lyrics = LyricService(netease: api, qq: QqLyrics());
    final audioCache = AudioCache.system(limit: () => settings.audioCacheLimit);
    unawaited(audioCache.init());
    if (!kIsWeb && Platform.isWindows) {
      // just_audio 在 Windows 上没有自带的实现，交给 media_kit（libmpv）播放。
      JustAudioMediaKit.title = AppInfo.name;
      JustAudioMediaKit.ensureInitialized(windows: true, linux: false);
    }
    if (!isNativeDesktop) await JustAudioEngine.configureSession();
    final player = PlayerController(
      engine: JustAudioEngine(),
      backend: NeteaseBackend(api, lyrics),
      settings: settings,
      cache: audioCache,
    );
    final account = AccountController(api: api, settings: settings);
    // 注册系统媒体会话：Android 前台服务 + 通知、iOS 锁屏、macOS 正在播放，保证后台持续播放。
    // Windows 上 audio_service 没有实现，改用 SMTC。
    WindowsMediaBridge? windowsMedia;
    if (!kIsWeb && Platform.isWindows) {
      windowsMedia = await WindowsMediaBridge.register(player);
    } else if (kIsWeb || !Platform.isLinux) {
      await SystemMediaBridge.register(player, account);
    }
    final desktop = isNativeDesktop ? await DesktopIntegration.start(player) : null;
    return AppServices(
      settings: settings,
      api: api,
      account: account,
      player: player,
      audioCache: audioCache,
      tracks: PlaylistTracks(api, store: FileTrackStore()),
      updates: UpdateChecker(settings: settings),
      desktop: desktop,
      windowsMedia: windowsMedia,
    );
  }

  final AppSettings settings;
  final NeteaseApi api;
  final AccountController account;
  final PlayerController player;

  /// 听歌缓存。测试里为 null。
  final AudioCache? audioCache;

  /// 歌单歌曲（带本地缓存）。
  final PlaylistTracks tracks;

  /// 检查 GitHub Release 更新。测试里为 null，不访问网络。
  final UpdateChecker? updates;

  /// 电脑端的托盘、快捷键、窗口。手机和测试里为 null。
  final DesktopIntegration? desktop;

  /// Windows 的系统媒体控制。其他平台为 null。
  final WindowsMediaBridge? windowsMedia;

  void dispose() {
    desktop?.dispose();
    windowsMedia?.dispose();
    player.dispose();
    audioCache?.dispose();
    account.dispose();
    api.close();
    updates?.dispose();
  }
}
