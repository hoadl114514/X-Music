import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/client_identity.dart';
import '../audio/audio_cache.dart';
import '../audio/audio_output.dart';
import '../data/models.dart';
import '../theme/app_theme.dart';

/// 本地设置，写入 SharedPreferences。
///
/// Cookie 也存在这里（明文，仅本机可读）。alpha 阶段够用，之后可以换成系统钥匙串。
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs);

  static Future<AppSettings> load() async => AppSettings(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _kCookie = 'cookie';
  static const _kFmMode = 'fm_mode';
  static const _kQuality = 'preferred_quality';
  static const _kLyricSource = 'lyric_source';
  static const _kLyricSourceOrder = 'lyric_source_order';
  static const _kLyricSourceOff = 'lyric_source_disabled';
  static const _kTranslation = 'show_translation';
  static const _kRomaji = 'show_romaji';
  static const _kSearchHistory = 'search_history';
  static const _kSyncRecent = 'sync_recent_plays';
  static const _kPlayMode = 'play_mode';
  static const _kSkippedUpdate = 'skipped_update';
  static const _kAudioCacheLimit = 'audio_cache_limit';
  static const _kDeviceId = 'device_id';
  static const _kThemeMode = 'theme_mode';
  static const _kDynamicColor = 'dynamic_color';
  static const _kSeedColor = 'seed_color';
  static const _kMobileQuality = 'mobile_quality';
  static const _kOutputDeviceType = 'output_device_type';
  static const _kOutputDeviceName = 'output_device_name';
  static const _kOutputBitDepth = 'output_bit_depth';
  static const _kOutputSampleRate = 'output_sample_rate';
  static const _kUsbExclusive = 'usb_exclusive';
  static const _kSharedPlaylists = 'shared_playlists';

  /// 搜索历史最多保留几条。
  static const searchHistoryLimit = 20;

  String get cookie => _prefs.getString(_kCookie) ?? '';
  set cookie(String v) => _set(() => _prefs.setString(_kCookie, v));

  /// 本机的设备号，所有接口共用。第一次用到时生成并保存，之后不变。
  String get deviceId {
    final saved = _prefs.getString(_kDeviceId);
    if (saved != null && saved.isNotEmpty) return saved;
    final id = ClientProfile.newDeviceId();
    _prefs.setString(_kDeviceId, id);
    return id;
  }

  /// 默认音质。歌曲没有这一档时自动降到它有的最高档。
  AudioQuality get preferredQuality =>
      AudioQuality.fromLevel(_prefs.getString(_kQuality)) ?? AudioQuality.exhigh;
  set preferredQuality(AudioQuality v) => _set(() => _prefs.setString(_kQuality, v.level));

  /// 私人 FM 的模式。
  FmMode get fmMode => FmMode.fromName(_prefs.getString(_kFmMode));
  set fmMode(FmMode v) => _set(() => _prefs.setString(_kFmMode, v.name));

  /// 移动网络下的音质；为 null 时和 [preferredQuality] 一样。
  AudioQuality? get mobileQuality => AudioQuality.fromLevel(_prefs.getString(_kMobileQuality));
  set mobileQuality(AudioQuality? v) => _set(
    () => v == null ? _prefs.remove(_kMobileQuality) : _prefs.setString(_kMobileQuality, v.level),
  );

  /// 指定的输出设备；为 null 时交给系统选择。
  AudioOutputDevice? get outputDevice {
    final type = _prefs.getInt(_kOutputDeviceType) ?? 0;
    if (type == 0) return null;
    return AudioOutputDevice(type: type, name: _prefs.getString(_kOutputDeviceName) ?? '');
  }

  set outputDevice(AudioOutputDevice? v) => _set(() {
    // 两个都先写进内存再等落盘，读的时候不会只看到一半。
    final type = _prefs.setInt(_kOutputDeviceType, v?.type ?? 0);
    final name = _prefs.setString(_kOutputDeviceName, v?.name ?? '');
    return Future.wait([type, name]).then((r) => r.every((ok) => ok));
  });

  OutputBitDepth get outputBitDepth => OutputBitDepth.byName(_prefs.getString(_kOutputBitDepth));
  set outputBitDepth(OutputBitDepth v) => _set(() => _prefs.setString(_kOutputBitDepth, v.name));

  /// 输出采样率；0 表示跟随音源。
  int get outputSampleRate => _prefs.getInt(_kOutputSampleRate) ?? 0;
  set outputSampleRate(int v) => _set(() => _prefs.setInt(_kOutputSampleRate, v));

  /// 在本机建的共建歌单 id。接口不一定标出共建歌单，自己建的先记下来。
  Set<String> get sharedPlaylistIds => {...?_prefs.getStringList(_kSharedPlaylists)};

  void addSharedPlaylist(String id) =>
      _set(() => _prefs.setStringList(_kSharedPlaylists, [...sharedPlaylistIds, id]));

  /// USB DAC 独占（bit-perfect）。
  bool get usbExclusive => _prefs.getBool(_kUsbExclusive) ?? false;
  set usbExclusive(bool v) => _set(() => _prefs.setBool(_kUsbExclusive, v));

  /// 默认的取歌词顺序。AMLL 按网易云 id 精确对应，排在要搜索匹配的 QQ 前面。
  static const defaultLyricSourceOrder = [LyricSource.netease, LyricSource.amll, LyricSource.qq];

  /// 所有歌词来源，按用户排的先后顺序（含已关闭的）。
  /// 没排过时用默认顺序，旧版设置的「默认歌词来源」放在最前。
  List<LyricSource> get lyricSourceOrder {
    final saved = [
      for (final n in _prefs.getStringList(_kLyricSourceOrder) ?? const <String>[])
        ?LyricSource.byName(n),
    ];
    final legacy = LyricSource.byName(_prefs.getString(_kLyricSource));
    final base = saved.isNotEmpty ? saved : [?legacy, ...defaultLyricSourceOrder];
    // 去重，并把新加的来源补到最后。
    return {...base, ...defaultLyricSourceOrder, ...LyricSource.values}.toList();
  }

  set lyricSourceOrder(List<LyricSource> v) =>
      _set(() => _prefs.setStringList(_kLyricSourceOrder, [for (final s in v) s.name]));

  /// 关闭的歌词来源：自动获取时跳过，但在播放页仍可手动切换。
  Set<LyricSource> get disabledLyricSources => {
    for (final n in _prefs.getStringList(_kLyricSourceOff) ?? const <String>[])
      ?LyricSource.byName(n),
  };

  /// 打开或关闭一个来源。至少保留一个打开的来源，关闭最后一个时不生效。
  void setLyricSourceEnabled(LyricSource s, bool enabled) {
    final off = disabledLyricSources;
    if (enabled) {
      off.remove(s);
    } else {
      if (lyricSourceOrder.where((x) => !off.contains(x) && x != s).isEmpty) return;
      off.add(s);
    }
    _set(() => _prefs.setStringList(_kLyricSourceOff, [for (final x in off) x.name]));
  }

  /// 自动获取歌词时依次尝试的来源：按顺序，去掉关闭的。
  List<LyricSource> get lyricSources {
    final off = disabledLyricSources;
    final on = lyricSourceOrder.where((s) => !off.contains(s)).toList();
    return on.isEmpty ? [lyricSourceOrder.first] : on;
  }

  /// 最优先的歌词来源。
  LyricSource get lyricSource => lyricSources.first;

  bool get showTranslation => _prefs.getBool(_kTranslation) ?? true;
  set showTranslation(bool v) => _set(() => _prefs.setBool(_kTranslation, v));

  bool get showRomaji => _prefs.getBool(_kRomaji) ?? true;
  set showRomaji(bool v) => _set(() => _prefs.setBool(_kRomaji, v));

  /// 搜索历史，最近的在前。
  List<String> get searchHistory => _prefs.getStringList(_kSearchHistory) ?? const [];

  /// 记一条搜索：挪到最前面，超出上限的丢掉。
  void addSearchHistory(String keyword) {
    final k = keyword.trim();
    if (k.isEmpty) return;
    final list = [k, ...searchHistory.where((e) => e != k)].take(searchHistoryLimit).toList();
    _set(() => _prefs.setStringList(_kSearchHistory, list));
  }

  void removeSearchHistory(String keyword) => _set(
    () => _prefs.setStringList(_kSearchHistory, [...searchHistory.where((e) => e != keyword)]),
  );

  void clearSearchHistory() => _set(() => _prefs.remove(_kSearchHistory));

  /// 登录后把听过的歌上报给网易云，同步到官方客户端的「最近播放」。
  bool get syncRecentPlays => _prefs.getBool(_kSyncRecent) ?? true;
  set syncRecentPlays(bool v) => _set(() => _prefs.setBool(_kSyncRecent, v));

  /// 上次选的播放模式（`PlayMode.name`：list / shuffle / one），没选过为 null。
  String? get playMode => _prefs.getString(_kPlayMode);
  set playMode(String? v) =>
      _set(() => v == null ? _prefs.remove(_kPlayMode) : _prefs.setString(_kPlayMode, v));

  /// 用户在更新提示里选了「跳过此版本」的标签，例如 v0.2.0。
  String? get skippedUpdate => _prefs.getString(_kSkippedUpdate);
  set skippedUpdate(String? v) =>
      _set(() => v == null ? _prefs.remove(_kSkippedUpdate) : _prefs.setString(_kSkippedUpdate, v));

  /// 听歌缓存上限（字节），默认 5 GB。0 表示不缓存。
  int get audioCacheLimit => _prefs.getInt(_kAudioCacheLimit) ?? AudioCache.defaultLimit;
  set audioCacheLimit(int v) => _set(() => _prefs.setInt(_kAudioCacheLimit, v < 0 ? 0 : v));

  /// 浅色 / 深色 / 跟随系统，默认跟随系统。
  AppThemeMode get themeMode => AppThemeMode.byName(_prefs.getString(_kThemeMode));
  set themeMode(AppThemeMode v) => _set(() => _prefs.setString(_kThemeMode, v.name));

  /// 动态取色：Android 12 及以上按壁纸取色。系统不支持时自动改用 [seedColor]。
  bool get dynamicColor => _prefs.getBool(_kDynamicColor) ?? true;
  set dynamicColor(bool v) => _set(() => _prefs.setBool(_kDynamicColor, v));

  /// 不用动态取色时的种子色，默认樱花粉。
  Color get seedColor => Color(_prefs.getInt(_kSeedColor) ?? AppTheme.sakura.toARGB32());
  set seedColor(Color v) => _set(() => _prefs.setInt(_kSeedColor, v.toARGB32()));

  /// SharedPreferences 的 set 会先更新内存缓存再异步落盘，所以读到的值立即是新的。
  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }
}
