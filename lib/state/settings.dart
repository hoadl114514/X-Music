import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/audio_cache.dart';
import '../data/models.dart';

/// 本地设置，写入 SharedPreferences。
///
/// Cookie 也存在这里（明文，仅本机可读）。alpha 阶段够用，之后可以换成系统钥匙串。
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs);

  static Future<AppSettings> load() async => AppSettings(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _kCookie = 'cookie';
  static const _kQuality = 'preferred_quality';
  static const _kLyricSource = 'lyric_source';
  static const _kTranslation = 'show_translation';
  static const _kRomaji = 'show_romaji';
  static const _kSearchHistory = 'search_history';
  static const _kSyncRecent = 'sync_recent_plays';
  static const _kPlayMode = 'play_mode';
  static const _kSkippedUpdate = 'skipped_update';
  static const _kAudioCacheLimit = 'audio_cache_limit';

  /// 搜索历史最多保留几条。
  static const searchHistoryLimit = 20;

  String get cookie => _prefs.getString(_kCookie) ?? '';
  set cookie(String v) => _set(() => _prefs.setString(_kCookie, v));

  /// 默认音质。歌曲没有这一档时自动降到它有的最高档。
  AudioQuality get preferredQuality =>
      AudioQuality.fromLevel(_prefs.getString(_kQuality)) ?? AudioQuality.exhigh;
  set preferredQuality(AudioQuality v) => _set(() => _prefs.setString(_kQuality, v.level));

  /// 默认歌词来源。取不到时自动换另一个来源。
  LyricSource get lyricSource =>
      LyricSource.byName(_prefs.getString(_kLyricSource)) ?? LyricSource.netease;
  set lyricSource(LyricSource v) => _set(() => _prefs.setString(_kLyricSource, v.name));

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

  /// SharedPreferences 的 set 会先更新内存缓存再异步落盘，所以读到的值立即是新的。
  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }
}
