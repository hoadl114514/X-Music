import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:netease_client/api/netease_api.dart';
import 'package:netease_client/app/services.dart';
import 'package:netease_client/audio/audio_cache.dart';
import 'package:netease_client/audio/audio_engine.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/state/account_controller.dart';
import 'package:netease_client/state/player_controller.dart';
import 'package:netease_client/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 记录调用、手动推进进度的假播放内核。
class FakeEngine implements AudioEngine {
  final loaded = <String>[];

  /// 每次 load 给的缓存位置（不缓存时为 null）。
  final cacheSlots = <CacheSlot?>[];
  Duration loadStart = Duration.zero;
  bool playing = false;
  Duration _position = Duration.zero;
  final _completed = StreamController<void>.broadcast();
  final _errors = StreamController<Object>.broadcast();

  /// 接下来这么多次 load 直接失败（模拟 Source error）。
  int failLoads = 0;

  void advance(Duration d) => _position += d;
  void complete() => _completed.add(null);

  /// 模拟播放中途出错。
  void error(Object e) => _errors.add(e);

  @override
  Future<void> load(String url, {Duration start = Duration.zero, CacheSlot? cacheTo}) async {
    if (failLoads > 0) {
      failLoads--;
      throw Exception('(0) Source error');
    }
    loaded.add(url);
    cacheSlots.add(cacheTo);
    loadStart = start;
    _position = start;
  }

  @override
  Future<void> play() async => playing = true;

  @override
  Future<void> pause() async => playing = false;

  @override
  Future<void> seek(Duration position) async => _position = position;

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Duration get position => _position;

  @override
  Duration? get duration => null;

  @override
  Stream<void> get completed => _completed.stream;

  @override
  Stream<Object> get errors => _errors.stream;

  @override
  Future<void> dispose() async {}
}

class FakeBackend implements PlaybackBackend {
  /// 每首歌提供的音质；没有配置的歌按 standard + exhigh。
  final qualityMap = <String, List<AudioQuality>>{};

  /// 账号最高能拿到的档位（模拟会员限制）。
  AudioQuality accountMax = AudioQuality.jymaster;

  /// 这些歌取不到地址（无版权）。
  final unavailable = <String>{};

  /// 这些歌接下来取地址时先网络失败几次。
  final urlFailures = <String, int>{};

  /// 这些歌只能试听。
  final trials = <String, ({Duration start, Duration end})>{};
  final lyricsMap = <(String, LyricSource), Lyrics>{};
  final urlRequests = <(String, AudioQuality)>[];
  final scrobbles = <({String id, Duration listened, String? sourceId})>[];
  final starts = <String>[];

  /// 模拟断网：取音质、取地址都抛网络错误。
  bool offline = false;
  int qualityRequests = 0;

  @override
  Future<void> startPlay(Song song, {String? sourceId}) async => starts.add(song.id);

  @override
  Future<void> scrobble(Song song, {required Duration listened, String? sourceId}) async =>
      scrobbles.add((id: song.id, listened: listened, sourceId: sourceId));

  @override
  Future<List<QualityInfo>> qualities(String songId) async {
    qualityRequests++;
    if (offline) throw Exception('Failed host lookup');
    return _qualities(songId);
  }

  List<QualityInfo> _qualities(String songId) => [
    for (final q in qualityMap[songId] ?? const [AudioQuality.standard, AudioQuality.exhigh])
      QualityInfo(quality: q, bitrate: 320000, size: 1 << 20),
  ];

  @override
  Future<SongUrl?> songUrl(String songId, AudioQuality quality) async {
    urlRequests.add((songId, quality));
    if (offline) throw Exception('Failed host lookup');
    final failures = urlFailures[songId] ?? 0;
    if (failures > 0) {
      urlFailures[songId] = failures - 1;
      throw const ApiException('网络请求失败：Connection reset');
    }
    if (unavailable.contains(songId)) return null;
    final actual = quality.index > accountMax.index ? accountMax : quality;
    return SongUrl(
      url: 'https://x/$songId/${actual.level}',
      quality: actual,
      trial: trials[songId],
    );
  }

  @override
  Future<Lyrics> lyrics(Song song, LyricSource source, {required bool fallback}) async {
    final order = [source, if (fallback) ...LyricSource.values.where((s) => s != source)];
    for (final s in order) {
      if (lyricsMap[(song.id, s)] case final l?) return l;
    }
    return Lyrics.empty;
  }
}

Song song(String id, {int seconds = 200}) => Song(
  id: id,
  title: '歌曲$id',
  artist: '歌手$id',
  album: '专辑$id',
  duration: Duration(seconds: seconds),
  palette: const [Color(0xFFF7A8C8), Color(0xFF8E7CF0)],
);

/// 每行 2 秒、每行 4 个字的逐字歌词，第一行从 10 秒开始。
Lyrics karaoke({int lines = 8, LyricSource source = LyricSource.netease}) {
  final out = <LyricLine>[];
  for (var i = 0; i < lines; i++) {
    final start = 10000 + i * 2000;
    out.add(
      LyricLine(
        start: Duration(milliseconds: start),
        end: Duration(milliseconds: start + 2000),
        words: [
          for (var w = 0; w < 4; w++)
            LyricWord(
              '字$w',
              Duration(milliseconds: start + w * 500),
              Duration(milliseconds: start + w * 500 + 500),
            ),
        ],
        translation: '第$i行翻译',
      ),
    );
  }
  return Lyrics(lines: out, source: source, wordSynced: true);
}

Future<AppSettings> testSettings([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return AppSettings.load();
}

/// 不联网的整套服务：网易云接口全部返回空结果。
Future<({AppServices services, FakeEngine engine, FakeBackend backend})> fakeServices({
  http.Client? client,
}) async {
  final settings = await testSettings();
  final api = NeteaseApi(
    client: client ?? MockClient((_) async => http.Response('{"code":200}', 200)),
  );
  final engine = FakeEngine();
  final backend = FakeBackend();
  final services = AppServices(
    settings: settings,
    api: api,
    account: AccountController(api: api, settings: settings),
    player: PlayerController(engine: engine, backend: backend, settings: settings),
    // 没有目录：设置页能显示缓存选项，但不读写文件。
    audioCache: AudioCache(directory: Future.value(null), limit: () => settings.audioCacheLimit),
  );
  return (services: services, engine: engine, backend: backend);
}
