import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/api/cookies.dart';
import 'package:netease_client/api/eapi_crypto.dart';
import 'package:netease_client/api/netease_api.dart';
import 'package:netease_client/data/models.dart';

/// 返回 [routes] 里路径匹配的响应，并记录请求。
NeteaseApi apiWith(
  Map<String, Object> routes, {
  List<http.Request>? seen,
  Map<String, String> cookies = const {},
}) => NeteaseApi(
  cookies: cookies,
  client: MockClient((r) async {
    seen?.add(r);
    final body = routes.entries.firstWhere((e) => r.url.path.endsWith(e.key)).value;
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

/// 解出 EAPI 请求体：接口路径和 JSON 参数。
({String path, Map<String, Object?> json}) eapiPayload(http.Request r) {
  final hex = r.bodyFields['params']!;
  final bytes = Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
  final plain = EapiCrypto.decrypt(bytes).split('-36cd479b6b5-');
  return (path: plain.first, json: jsonDecode(plain[1]) as Map<String, Object?>);
}

Map<String, Object> rawSong(int id, {int artistId = 7, int albumId = 9}) => {
  'id': id,
  'name': '歌$id',
  'ar': [
    {'id': artistId, 'name': '歌手'},
  ],
  'al': {'id': albumId, 'name': '专辑', 'picUrl': 'http://p1.music.126.net/a.jpg'},
  'dt': 1000,
};

void main() {
  test('songs carry artist and album ids for navigation', () async {
    final api = apiWith({
      '/recommend/songs': {
        'code': 200,
        'data': {
          'dailySongs': [rawSong(1)],
        },
      },
    });
    final s = (await api.dailySongs()).single;
    expect(s.artists.single.id, '7');
    expect(s.artists.single.name, '歌手');
    expect(s.albumId, '9');
    expect(s.coverUrl, 'https://p1.music.126.net/a.jpg');
  });

  test('personal FM reads the old song format (artists / album)', () async {
    final api = apiWith({
      '/radio/get': {
        'code': 200,
        'data': [
          {
            'id': 3,
            'name': 'FM',
            'artists': [
              {'id': 1, 'name': 'A'},
            ],
            'album': {'id': 2, 'name': 'B', 'picUrl': 'https://x/y.jpg'},
            'duration': 2000,
          },
        ],
      },
    });
    final s = (await api.personalFm()).single;
    expect(s.artist, 'A');
    expect(s.albumId, '2');
    expect(s.duration, const Duration(seconds: 2));
  });

  test('recommendPlaylists uses daily resources when logged in, personalized otherwise', () async {
    final seen = <http.Request>[];
    final routes = <String, Object>{
      '/recommend/resource': {
        'code': 200,
        'recommend': [
          {'id': 1, 'name': '私人雷达', 'picUrl': 'http://p/x.jpg', 'playcount': 5, 'trackCount': 3},
        ],
      },
      '/personalized/playlist': {
        'code': 200,
        'result': [
          {'id': 2, 'name': '通用', 'picUrl': 'http://p/y.jpg', 'playCount': 8},
        ],
      },
    };
    final logged = apiWith(routes, seen: seen, cookies: {'MUSIC_U': 'x'});
    final p = (await logged.recommendPlaylists()).single;
    expect(p.name, '私人雷达');
    expect(p.playCount, 5);
    expect(p.coverUrl, 'https://p/x.jpg');

    final anon = apiWith(routes, seen: seen);
    expect((await anon.recommendPlaylists()).single.name, '通用');
    expect(seen.last.url.path, endsWith('/personalized/playlist'));
  });

  test('toplists expose the update frequency', () async {
    final api = apiWith({
      '/toplist': {
        'code': 200,
        'list': [
          {'id': 19723756, 'name': '飙升榜', 'updateFrequency': '每天更新', 'coverImgUrl': 'http://c'},
        ],
      },
    });
    final t = (await api.toplists()).single;
    expect(t.name, '飙升榜');
    expect(t.description, '每天更新');
  });

  test('playRecord picks week or all data with play counts', () async {
    final seen = <http.Request>[];
    final api = apiWith({
      '/play/record': {
        'code': 200,
        'weekData': [
          {'playCount': 37, 'song': rawSong(1)},
        ],
        'allData': [
          {'playCount': 159, 'song': rawSong(2)},
        ],
      },
    }, seen: seen);
    final week = await api.playRecord(42);
    expect(week.single.playCount, 37);
    expect(seen.last.bodyFields['type'], '1');
    final all = await api.playRecord(42, weekly: false);
    expect(all.single.song.id, '2');
    expect(seen.last.bodyFields['type'], '0');
  });

  test('recentSongs unwraps data.list[].data', () async {
    final api = apiWith({
      '/song/list': {
        'code': 200,
        'data': {
          'list': [
            {'resourceId': '1', 'data': rawSong(1)},
          ],
        },
      },
    });
    expect((await api.recentSongs()).single.title, '歌1');
  });

  test('artistDetail and album parse info, album songs get the album cover', () async {
    final api = apiWith({
      '/artist/6452': {
        'code': 200,
        'artist': {
          'id': 6452,
          'name': '周杰伦',
          'img1v1Url': 'http://a.jpg',
          'briefDesc': '简介',
          'musicSize': 589,
          'albumSize': 47,
        },
        'hotSongs': [rawSong(1)],
      },
      '/album/18903': {
        'code': 200,
        'album': {
          'id': 18903,
          'name': '七里香',
          'picUrl': 'http://cover.jpg',
          'publishTime': 1091462400000,
          'size': 10,
          'artists': [
            {'id': 6452, 'name': '周杰伦'},
          ],
        },
        'songs': [
          {
            'id': 5,
            'name': '我的地盘',
            'ar': [
              {'id': 6452, 'name': '周杰伦'},
            ],
            'al': {'id': 18903, 'name': '七里香'},
            'dt': 1,
          },
        ],
      },
    });
    final a = await api.artistDetail('6452');
    expect(a.artist.avatarUrl, 'https://a.jpg');
    expect(a.artist.songCount, 589);
    expect(a.hotSongs, hasLength(1));

    final al = await api.album('18903');
    expect(al.album.artist, '周杰伦');
    expect(al.album.publishTime!.year, 2004);
    expect(al.songs.single.coverUrl, 'https://cover.jpg');
    expect(al.songs.single.albumId, '18903');
  });

  test('addToPlaylist sends op, pid and numeric track ids; errors surface', () async {
    final seen = <http.Request>[];
    final ok = apiWith({
      '/manipulate/tracks': {'code': 200},
    }, seen: seen);
    await ok.addToPlaylist('100', ['1', '2']);
    // 和 api-enhanced 一样先走 EAPI。
    expect(seen.single.url.path, '/eapi/playlist/manipulate/tracks');
    final json = eapiPayload(seen.single).json;
    expect(json, containsPair('op', 'add'));
    expect(json, containsPair('pid', '100'));
    expect(json, containsPair('trackIds', '[1,2]'));

    final blocked = apiWith({
      '/manipulate/tracks': {'code': -462, 'message': '检测到您的网络环境存在风险，请稍后再试'},
    });
    await expectLater(
      blocked.addToPlaylist('100', ['1']),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', -462)),
    );
  });

  test('search by type reads the matching result list and count', () async {
    final api = apiWith({
      '/cloudsearch/pc': {
        'code': 200,
        'result': {
          'artistCount': 84,
          'artists': [
            {'id': 6452, 'name': '周杰伦', 'picUrl': 'http://p.jpg'},
          ],
        },
      },
    });
    final r = await api.searchArtists('周杰伦');
    expect(r.total, 84);
    expect(r.items.single.avatarUrl, 'https://p.jpg');
  });

  test('parseSetCookie splits folded headers without breaking Expires dates', () {
    const header =
        'MUSIC_U=abc; Max-Age=1296000; Expires=Wed, 29 Oct 2036 10:03:26 GMT; Path=/,'
        '__csrf=x1; Path=/, NMTID=n=1; Domain=.music.163.com,MUSIC_A_T=deleted; Path=/';
    expect(parseSetCookie(header), {'MUSIC_U': 'abc', '__csrf': 'x1', 'NMTID': 'n=1'});
    expect(parseSetCookie(null), isEmpty);
  });

  test('qrCheck maps status codes and returns cookies on 803', () async {
    var code = 801;
    final seen = <http.Request>[];
    final api = NeteaseApi(
      cookies: {'MUSIC_U': 'old'},
      client: MockClient((r) async {
        seen.add(r);
        return http.Response(
          jsonEncode({'code': code, 'nickname': '某人', 'avatarUrl': 'http://a.jpg'}),
          200,
          headers: {
            'content-type': 'application/json',
            if (code == 803) 'set-cookie': 'MUSIC_U=new; Path=/,__csrf=c; Path=/',
          },
        );
      }),
    );
    expect((await api.qrCheck('k')).status, QrStatus.waiting);
    // 登录接口不带旧账号的 Cookie。
    expect(seen.last.headers['Cookie'], isNot(contains('MUSIC_U')));
    code = 802;
    final scanned = await api.qrCheck('k');
    expect(scanned.status, QrStatus.scanned);
    expect(scanned.nickname, '某人');
    code = 803;
    final ok = await api.qrCheck('k');
    expect(ok.status, QrStatus.confirmed);
    expect(ok.cookies, {'MUSIC_U': 'new', '__csrf': 'c'});
    code = 800;
    expect((await api.qrCheck('k')).status, QrStatus.expired);
    code = 500;
    await expectLater(api.qrCheck('k'), throwsA(isA<ApiException>()));
  });

  test('search suggestions read keywords and quick results', () async {
    final api = apiWith({
      '/suggest/keyword': {
        'code': 200,
        'result': {
          'allMatch': [
            {'keyword': '周杰伦'},
            {'keyword': '周杰伦晴天'},
          ],
        },
      },
      '/suggest/web': {
        'code': 200,
        'result': {
          'songs': [
            {
              'id': 1,
              'name': '晴天',
              'artists': [
                {'id': 6452, 'name': '周杰伦'},
              ],
              'album': {'id': 2, 'name': '叶惠美'},
              'duration': 1,
            },
          ],
          'artists': [
            {'id': 6452, 'name': '周杰伦'},
          ],
        },
      },
    });
    expect(await api.searchKeywords('周杰'), ['周杰伦', '周杰伦晴天']);
    final q = await api.searchSuggest('周杰');
    expect(q.songs.single.title, '晴天');
    expect(q.artists.single.name, '周杰伦');
    expect(q.isEmpty, isFalse);
  });

  test('playlistDetail falls back to the first song cover when the playlist has none', () async {
    final api = apiWith({
      '/playlist/detail': {
        'code': 200,
        'playlist': {
          'id': 5,
          'name': '空封面',
          'trackIds': [
            {'id': 1},
          ],
        },
      },
      '/song/detail': {
        'code': 200,
        'songs': [rawSong(1)],
      },
    });
    final r = await api.playlistDetail('5');
    expect(r.playlist.coverUrl, 'https://p1.music.126.net/a.jpg');
  });

  test('playlistFirstCover reads only the first track', () async {
    final seen = <http.Request>[];
    final api = apiWith({
      '/playlist/detail': {
        'code': 200,
        'playlist': {
          'id': 5,
          'tracks': [rawSong(1)],
        },
      },
    }, seen: seen);
    expect(await api.playlistFirstCover('5'), 'https://p1.music.126.net/a.jpg');
    expect(seen.single.bodyFields['n'], '1');
  });

  test('comments parse users, replies, location and paging cursor', () async {
    final seen = <http.Request>[];
    final api = apiWith({
      '/v2/resource/comments': {
        'code': 200,
        'data': {
          'totalCount': 312072,
          'hasMore': true,
          'cursor': 'normalHot#20',
          'comments': [
            {
              'commentId': 11,
              'content': '好听',
              'time': 1638897393811,
              'likedCount': 444020,
              'liked': true,
              'replyCount': 3,
              'user': {'userId': 7, 'nickname': '某人', 'avatarUrl': 'http://p3.music.126.net/u.jpg'},
              'beReplied': [
                {
                  'beRepliedCommentId': 9,
                  'content': null,
                  'user': {'nickname': '楼主'},
                },
              ],
              'ipLocation': {'location': '广东'},
            },
          ],
        },
      },
    }, seen: seen);
    final page = await api.comments(
      'R_SO_4_1',
      sort: CommentSort.hot,
      pageNo: 2,
      cursor: 'normalHot#20',
    );
    expect(seen.single.bodyFields, containsPair('sortType', '2'));
    expect(seen.single.bodyFields, containsPair('cursor', 'normalHot#20'));
    expect(seen.single.bodyFields, containsPair('pageNo', '2'));
    expect(page.total, 312072);
    expect(page.hasMore, isTrue);
    expect(page.cursor, 'normalHot#20');
    final c = page.comments.single;
    expect(c.id, 11);
    expect(c.user.nickname, '某人');
    expect(c.user.avatarUrl, 'https://p3.music.126.net/u.jpg');
    expect(c.liked, isTrue);
    expect(c.replyCount, 3);
    expect(c.location, '广东');
    expect(c.replyTo?.id, 9);
    expect(c.replyTo?.content, '该评论已删除');
  });

  test('floor comments use the returned time as cursor', () async {
    final seen = <http.Request>[];
    final api = apiWith({
      '/comment/floor/get': {
        'code': 200,
        'data': {
          'totalCount': 2,
          'hasMore': false,
          'time': 1638964850039,
          'comments': [
            {
              'commentId': 12,
              'content': '回复',
              'time': 1,
              'user': {'userId': 8, 'nickname': 'B'},
            },
          ],
        },
      },
    }, seen: seen);
    final page = await api.floorComments('R_SO_4_1', 11);
    expect(seen.single.bodyFields['time'], '-1');
    expect(seen.single.bodyFields['parentCommentId'], '11');
    expect(page.cursor, '1638964850039');
    expect(page.comments.single.content, '回复');
  });

  test('posting a reply hits the reply endpoint with the comment id', () async {
    final seen = <http.Request>[];
    final api = apiWith({
      '/comments/reply': {
        'code': 200,
        'comment': {
          'commentId': 99,
          'content': '你好',
          'time': 1,
          'user': {'userId': 1, 'nickname': '我'},
        },
      },
    }, seen: seen);
    final c = await api.postComment('R_SO_4_1', '你好', replyTo: 11);
    expect(seen.single.url.path, '/eapi/resource/comments/reply');
    final (:path, :json) = eapiPayload(seen.single);
    expect(path, '/api/resource/comments/reply');
    expect(json, containsPair('threadId', 'R_SO_4_1'));
    expect(json, containsPair('content', '你好'));
    expect(json, containsPair('commentId', '11'));
    expect(c?.id, 99);
  });

  test('scrobble sends startplay then play logs to clientlog as the macOS client', () async {
    final seen = <http.Request>[];
    final api = apiWith(
      {
        '/feedback/weblog': {'code': 200, 'data': 'success'},
      },
      seen: seen,
      cookies: {'MUSIC_U': 'u', '__csrf': 'c'},
    );
    await api.startPlay('42', sourceId: 'pl1');
    await api.scrobble('42', seconds: 95, sourceId: 'pl1');
    expect(seen, hasLength(2));
    for (final r in seen) {
      expect(r.url.toString(), 'https://clientlog.music.163.com/eapi/feedback/weblog');
      expect(r.headers['Cookie'], allOf(contains('os=osx'), contains('MUSIC_U=u')));
    }
    // 解出 EAPI 请求体里的 JSON。
    Map<String, Object?> payload(http.Request r) {
      final hex = r.bodyFields['params']!;
      final bytes = Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
      final plain = EapiCrypto.decrypt(bytes).split('-36cd479b6b5-');
      expect(plain.first, '/api/feedback/weblog');
      return jsonDecode(plain[1]) as Map<String, Object?>;
    }

    Map<Object?, Object?> log(http.Request r) =>
        (jsonDecode(payload(r)['logs']! as String) as List).single as Map;
    expect(log(seen[0])['action'], 'startplay');
    expect((log(seen[0])['json'] as Map)['content'], 'id=pl1');
    final play = log(seen[1]);
    expect(play['action'], 'play');
    final json = play['json'] as Map;
    expect(json['id'], 42);
    expect(json['time'], 95);
    expect(json['sourceId'], 'pl1');
    final header = jsonDecode(payload(seen[1])['header']! as String) as Map;
    expect(header['os'], 'osx');
    expect(header['MUSIC_U'], 'u');
  });

  test('writes aligned with api-enhanced fall back to the plain API when refused', () async {
    final seen = <http.Request>[];
    final api = NeteaseApi(
      cookies: const {'MUSIC_U': 'u'},
      client: MockClient((r) async {
        seen.add(r);
        final refused = !r.url.path.startsWith('/api/');
        return http.Response(
          jsonEncode(refused ? {'code': 400, 'message': '不支持'} : {'code': 200}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await api.addToPlaylist('100', ['1']);
    await api.setPlaylistSubscribed('100', true);
    await api.deleteComment('R_SO_4_1', 5);
    await api.likeComment('R_SO_4_1', 5, true);
    await api.deleteEvent(9);
    await api.fmTrash('3');
    expect(seen.map((r) => r.url.path), [
      '/eapi/playlist/manipulate/tracks',
      '/api/playlist/manipulate/tracks',
      '/eapi/playlist/subscribe',
      '/api/playlist/subscribe',
      '/eapi/resource/comments/delete',
      '/api/resource/comments/delete',
      '/weapi/v1/comment/like',
      '/api/v1/comment/like',
      '/weapi/event/delete',
      '/api/event/delete',
      '/weapi/radio/trash/add',
      '/api/radio/trash/add',
    ]);
  });

  test('a network failure is not retried, so a write is never sent twice', () async {
    var calls = 0;
    final api = NeteaseApi(
      client: MockClient((r) async {
        calls++;
        throw http.ClientException('timeout');
      }),
    );
    await expectLater(
      api.postComment('R_SO_4_1', 'hi'),
      throwsA(isA<ApiException>().having((e) => e.network, 'network', isTrue)),
    );
    expect(calls, 1);
  });
}
