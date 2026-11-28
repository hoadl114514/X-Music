import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/api/netease_api.dart';
import 'package:netease_client/audio/listen_cache.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/data/track_cache.dart';
import 'package:netease_client/lyrics/amll_lyrics.dart';
import 'package:netease_client/lyrics/lyric_service.dart';
import 'package:netease_client/lyrics/qq_lyrics.dart';
import 'package:netease_client/state/account_controller.dart';
import 'package:netease_client/widgets/image_disk_cache.dart';

import 'support/fakes.dart';

class _Netease extends NeteaseApi {
  var calls = 0;

  @override
  Future<Map<String, String>> lyricTexts(String songId) async {
    calls++;
    return {
      for (final k in const ['lrc', 'yrc', 'tlyric', 'romalrc', 'ytlrc', 'yromalrc']) k: '',
      'lrc': '[00:01.00]星\n[00:05.00]空',
      'tlyric': '[00:01.00]star',
    };
  }
}

const _song = Song(id: '42', title: 't', artist: 'a', album: '', duration: Duration(minutes: 3));

void main() {
  group('DataCache.watch', () {
    test('先发缓存，有变化再发新的', () async {
      final cache = DataCache();
      await cache.write('k', [1, 2]);
      final got = await cache
          .watch<List<int>>(
            'k',
            fetch: () async => [1, 2, 3],
            encode: (v) => v,
            decode: (j) => (j as List).cast<int>(),
          )
          .toList();
      expect(got, [
        [1, 2],
        [1, 2, 3],
      ]);
    });

    test('和缓存一样时只发一次', () async {
      final cache = DataCache();
      await cache.write('k', [1]);
      final got = await cache
          .watch<List<int>>(
            'k',
            fetch: () async => [1],
            encode: (v) => v,
            decode: (j) => (j as List).cast<int>(),
          )
          .toList();
      expect(got, [
        [1],
      ]);
    });

    test('联网失败时先发的缓存还在，再报错', () async {
      final cache = DataCache();
      await cache.write('k', [1]);
      final got = <List<int>>[];
      Object? error;
      final stream = cache.watch<List<int>>(
        'k',
        fetch: () async => throw const ApiException('断网'),
        encode: (v) => v,
        decode: (j) => (j as List).cast<int>(),
      );
      try {
        await for (final v in stream) {
          got.add(v);
        }
      } catch (e) {
        error = e;
      }
      expect(got, [
        [1],
      ]);
      expect(error, isA<ApiException>());
    });
  });

  test('歌词存进缓存，换一个服务实例也不用再联网', () async {
    final store = MemoryTrackStore();
    final netease = _Netease();
    LyricService service() => LyricService(
      netease: netease,
      qq: QqLyrics(client: MockClient((_) async => http.Response('', 500))),
      amll: AmllLyrics(client: MockClient((_) async => http.Response('', 404))),
      store: DataCache(store: store),
    );
    final first = await service().fetch(_song, LyricSource.netease, fallback: false);
    expect(netease.calls, 1);
    final second = await service().fetch(_song, LyricSource.netease, fallback: false);
    expect(netease.calls, 1);
    expect(second.lines.map((l) => l.text), first.lines.map((l) => l.text));
    expect(second.lines.first.translation, 'star');
    expect(second.source, LyricSource.netease);
  });

  test('歌词 JSON 来回不丢逐字、注音、对唱和背景人声', () {
    const lyrics = Lyrics(
      lines: [
        LyricLine(
          start: Duration(milliseconds: 1000),
          end: Duration(milliseconds: 2000),
          words: [
            LyricWord('星', Duration(milliseconds: 1000), Duration(milliseconds: 1500), ruby: 'ほし'),
          ],
          romaji: 'hoshi',
          duet: true,
          background: LyricLine(
            start: Duration(milliseconds: 1200),
            end: Duration(milliseconds: 1800),
            words: [LyricWord('ah', Duration(milliseconds: 1200), Duration(milliseconds: 1800))],
          ),
        ),
      ],
      source: LyricSource.amll,
      wordSynced: true,
    );
    final back = Lyrics.fromJson(jsonDecode(jsonEncode(lyrics.toJson())))!;
    final l = back.lines.single;
    expect(back.source, LyricSource.amll);
    expect(back.wordSynced, isTrue);
    expect(l.words.single.ruby, 'ほし');
    expect(l.words.single.end, const Duration(milliseconds: 1500));
    expect(l.romaji, 'hoshi');
    expect(l.duet, isTrue);
    expect(l.background!.text, 'ah');
  });

  test('启动时先显示缓存的账号和歌单，联网失败也不掉登录', () async {
    final settings = await testSettings({'cookie': 'MUSIC_U=x'});
    final data = DataCache();
    await data.write('account', {
      'v': 1,
      'profile': const UserProfile(userId: 7, nickname: '我').toJson(),
      'playlists': [
        const Playlist(id: 'p1', name: '我喜欢的音乐', playCount: 0, isLikedList: true).toJson(),
        const Playlist(id: 'p2', name: '共建', playCount: 0, creatorId: 7, shared: true).toJson(),
      ],
      'liked': ['s1'],
    });
    final api = NeteaseApi(client: MockClient((_) async => throw Exception('offline')));
    final account = AccountController(api: api, settings: settings, data: data);
    await account.restore();
    expect(account.isLoggedIn, isTrue);
    expect(account.profile!.nickname, '我');
    expect(account.likedPlaylist?.id, 'p1');
    expect(account.sharedPlaylists.single.id, 'p2');
    expect(account.isLiked('s1'), isTrue);
  });

  test('清空听歌缓存时数据和图片一起清掉', () async {
    ImageDiskCache.memory = {'u': Uint8List(100)};
    addTearDown(ImageDiskCache.resetDirectory);
    final data = DataCache();
    await data.write('k', 'v' * 50);
    final cache = ListenCache(data: data);
    await cache.refresh();
    expect(cache.imageBytes, 100);
    expect(cache.dataBytes, greaterThan(50));
    await cache.clear();
    await cache.refresh();
    expect(cache.usedBytes, 0);
    expect(await data.read('k', (j) => j), isNull);
  });

  test('音质列表先用缓存，开歌不用等接口', () async {
    final f = await fakeServices();
    f.backend.qualityMap['1'] = [AudioQuality.exhigh, AudioQuality.lossless];
    final player = f.services.player;
    await player.playQueue([song('1')], title: 't');
    await player.pause();
    expect(f.backend.qualityRequests, 1);
    await pumpEventQueue();
    expect(await f.services.data.read('q_1', (j) => j), isA<List<Object?>>());
  });
}
