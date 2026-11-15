import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';

import '../api/netease_api.dart';
import '../data/models.dart';
import '../state/account_controller.dart';
import '../state/player_controller.dart';

/// 把 [PlayerController] 注册成系统的媒体会话：
/// Android 上是前台服务 + 媒体通知（保证切到后台、锁屏后继续播放），
/// iOS 上是控制中心 / 锁屏的正在播放信息。
/// 通知栏、锁屏、耳机线控、蓝牙按键的操作都转发回 [PlayerController]。
///
/// 播放逻辑仍然只在 [PlayerController] 里，这里只做双向同步。
/// 通知栏原来「停止」的位置放喜欢 / 取消喜欢，状态来自 [AccountController]。
class SystemMediaBridge extends BaseAudioHandler with SeekHandler {
  SystemMediaBridge(this._player, [this._account]) {
    _player.addListener(_sync);
    _account?.addListener(_sync);
    _sync();
  }

  final PlayerController _player;
  final AccountController? _account;

  /// 通知栏喜欢按钮的自定义动作名。
  static const likeAction = 'like';

  static final _likeControl = MediaControl.custom(
    androidIcon: 'drawable/ic_notif_like',
    label: '喜欢',
    name: likeAction,
  );
  static final _unlikeControl = MediaControl.custom(
    androidIcon: 'drawable/ic_notif_liked',
    label: '取消喜欢',
    name: likeAction,
  );

  /// 注册系统媒体服务。必须在 runApp 之前调用一次。
  static Future<SystemMediaBridge> register(PlayerController player, AccountController account) =>
      AudioService.init(
        builder: () => SystemMediaBridge(player, account),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'io.github.hoadl114514.netease_client.playback',
          androidNotificationChannelName: '音乐播放',
          // 白色单色小图标。按名字查找，android/app/src/main/res/raw/keep.xml 里保留了它。
          androidNotificationIcon: 'drawable/ic_stat_music',
          // 暂停时也保持前台服务：Android 12+ 不允许应用从后台重新拉起前台服务，
          // 否则暂停后用耳机 / 蓝牙恢复播放会失败。
          androidStopForegroundOnPause: false,
        ),
      );

  static const _channel = MethodChannel('netease_client/system_media');

  /// Android 上通知是否开着。关着时媒体通知发不出来，控制中心 / 锁屏看不到播放卡片。
  /// 其他平台、或者原生端没有实现时视为开着。
  static Future<bool> notificationsEnabled() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('notificationsEnabled') ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  /// 打开本应用的系统通知设置。
  static Future<void> openNotificationSettings() async {
    try {
      await _channel.invokeMethod<void>('openNotificationSettings');
    } on MissingPluginException {
      // 非 Android。
    }
  }

  String? _songId;
  ({bool playing, bool loading, int index, AudioQuality? quality, bool liked})? _last;
  Duration _lastPosition = Duration.zero;
  DateTime _lastUpdate = DateTime.now();

  /// 控制器每 50ms 通知一次，这里只在状态真正变化（播放 / 暂停、切歌、拖动进度）时推给系统；
  /// 正常播放时系统会按 updatePosition + updateTime 自己外推进度。
  void _sync() {
    final song = _player.current;
    if (song == null) return;
    if (song.id != _songId) {
      _songId = song.id;
      mediaItem.add(_item(song));
    }
    final state = (
      playing: _player.isPlaying,
      loading: _player.isLoading,
      index: _player.index,
      quality: _player.quality,
      liked: _account?.isLiked(song.id) ?? false,
    );
    final now = DateTime.now();
    final expected = state.playing && _last?.playing == true
        ? _lastPosition + now.difference(_lastUpdate)
        : _lastPosition;
    final jumped = (_player.position - expected).abs() > const Duration(seconds: 1);
    if (state == _last && !jumped) return;
    // 试听片段的时长要等加载完才知道。
    if (_last?.loading == true && !state.loading) mediaItem.add(_item(song));
    _last = state;
    _lastPosition = _player.position;
    _lastUpdate = now;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          state.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          state.liked ? _unlikeControl : _likeControl,
        ],
        systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: state.loading ? AudioProcessingState.loading : AudioProcessingState.ready,
        playing: state.playing,
        updatePosition: _player.position,
        updateTime: now,
        queueIndex: state.index,
      ),
    );
  }

  MediaItem _item(Song song) => MediaItem(
    id: song.id,
    title: song.title,
    artist: song.artist,
    album: song.album,
    duration: _player.current?.id == song.id ? _player.duration : song.duration,
    artUri: song.coverUrl == null ? null : Uri.parse(sizedImage(song.coverUrl!, 512)),
  );

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> skipToNext() => _player.next();

  @override
  Future<void> skipToPrevious() => _player.previous(restart: false);

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name != likeAction) return super.customAction(name, extras);
    final song = _player.current;
    final account = _account;
    if (song == null || account == null) return null;
    try {
      await account.toggleLike(song.id);
    } on ApiException catch (e) {
      _player.notice(e.message);
    }
    return null;
  }

  @override
  Future<void> stop() async {
    await _player.pause();
    playbackState.add(
      playbackState.value.copyWith(processingState: AudioProcessingState.idle, playing: false),
    );
    _last = null;
    await super.stop();
  }
}
