import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/api/netease_api.dart';

NeteaseApi _api(Map<String, Object> routes, {List<http.Request>? seen}) => NeteaseApi(
  cookies: const {'MUSIC_U': 'u'},
  client: MockClient((r) async {
    seen?.add(r);
    final body = routes.entries
        .firstWhere(
          (e) => r.url.path.endsWith(e.key),
          orElse: () => const MapEntry('', {'code': 200}),
        )
        .value;
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _user(int id, {int userType = 0}) => {
  'userId': id,
  'nickname': '用户$id',
  'avatarUrl': 'http://p1.music.126.net/$id.jpg',
  'userType': userType,
};

void main() {
  test('events parse text, pictures, shared song and forwarded events', () async {
    final api = _api({
      '/api/v1/event/get': {
        'code': 200,
        'more': true,
        'lasttime': 123,
        'events': [
          {
            'id': 1,
            'type': 18,
            'eventTime': 1700000000000,
            'user': _user(10, userType: 4),
            'json': jsonEncode({
              'msg': '好听',
              'song': {
                'id': 5,
                'name': '歌',
                'artists': [
                  {'id': 2, 'name': '歌手'},
                ],
                'album': {'id': 3, 'name': '专辑', 'picUrl': 'http://p1.music.126.net/c.jpg'},
              },
            }),
            'pics': [
              {'originUrl': 'http://p1.music.126.net/p.jpg'},
            ],
            'info': {
              'likedCount': 4,
              'liked': true,
              'commentCount': 2,
              'commentThread': {'id': 'A_EV_2_1_10'},
            },
          },
          {
            'id': 2,
            'type': 22,
            'eventTime': 1700000001000,
            'user': _user(11),
            'json': jsonEncode({
              'msg': '转发一下',
              'event': {
                'id': 1,
                'type': 13,
                'eventTime': 1700000000000,
                'user': _user(12),
                'json': jsonEncode({
                  'msg': '我的歌单',
                  'playlist': {'id': 9, 'name': '歌单', 'trackCount': 3},
                }),
              },
            }),
            'threadId': 'A_EV_2_2_11',
          },
          // 没有作者的脏数据跳过。
          {'id': 3, 'type': 35, 'json': '{}'},
        ],
      },
    });
    final page = await api.followFeed();
    expect(page.more, isTrue);
    expect(page.lasttime, 123);
    expect(page.events, hasLength(2));

    final first = page.events.first;
    expect(first.user.musician, isTrue);
    expect(first.user.avatarUrl, 'https://p1.music.126.net/10.jpg');
    expect(first.action, '分享单曲');
    expect(first.text, '好听');
    expect(first.pics.single, 'https://p1.music.126.net/p.jpg');
    expect(first.song!.title, '歌');
    expect(first.song!.coverUrl, 'https://p1.music.126.net/c.jpg');
    expect(first.threadId, 'A_EV_2_1_10');
    expect(first.liked, isTrue);
    expect(first.likedCount, 4);

    final fwd = page.events.last;
    expect(fwd.user.musician, isFalse);
    expect(fwd.action, '转发');
    expect(fwd.threadId, 'A_EV_2_2_11');
    expect(fwd.forwarded!.user.nickname, '用户12');
    expect(fwd.forwarded!.playlist!.name, '歌单');
  });

  test('user events page by lasttime', () async {
    final seen = <http.Request>[];
    final api = _api({
      '/api/event/get/7': {'code': 200, 'events': <Object>[], 'more': false, 'lasttime': 0},
    }, seen: seen);
    await api.userEvents(7, lasttime: 999);
    expect(seen.single.bodyFields['time'], '999');
  });

  test('follow tries XEAPI, then PC EAPI, then WEAPI; unfollow goes through WEAPI', () async {
    final seen = <http.Request>[];
    final api = NeteaseApi(
      cookies: const {'MUSIC_U': 'u'},
      client: MockClient((r) async {
        seen.add(r);
        if (r.url.host == 'ac.dun.163yun.com') return http.Response('x', 200);
        // 公钥注册失败，XEAPI 这一步报错，接着试 EAPI。
        if (r.url.path == '/api/bsr/sk/get') return _json({'code': 400});
        if (r.url.path.startsWith('/eapi/')) return _json({'code': 250, 'message': '关注异常'});
        return _json({'code': 200});
      }),
    );
    await api.setFollowed(42, true);
    await api.setFollowed(42, false);
    expect(seen.where((r) => r.url.host != 'ac.dun.163yun.com').map((r) => r.url.toString()), [
      'https://interface.music.163.com/api/bsr/sk/get',
      'https://interface3.music.163.com/eapi/user/follow/42',
      'https://music.163.com/weapi/user/follow/42',
      'https://music.163.com/weapi/user/delfollow/42',
    ]);
    final form = seen.last.bodyFields;
    expect(form.keys, unorderedEquals(['params', 'encSecKey']));
    expect(form['encSecKey'], hasLength(256));
  });

  test('follow stops at risk control instead of trying more transports', () async {
    final seen = <http.Request>[];
    final api = NeteaseApi(
      cookies: const {'MUSIC_U': 'u'},
      client: MockClient((r) async {
        seen.add(r);
        if (r.url.host == 'ac.dun.163yun.com') return http.Response('x', 200);
        return _json({'code': -462, 'message': '检测到您的网络环境存在风险'});
      }),
    );
    await expectLater(
      api.setFollowed(42, true),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', -462)),
    );
    expect(seen.where((r) => r.url.path.contains('/user/follow/')), isEmpty);
  });

  test('artist follow goes through WEAPI artist/sub and artist/unsub', () async {
    final seen = <http.Request>[];
    final api = _api({}, seen: seen);
    await api.setArtistFollowed('12487174', true);
    await api.setArtistFollowed('12487174', false);
    expect(seen.map((r) => r.url.toString()), [
      'https://music.163.com/weapi/artist/sub',
      'https://music.163.com/weapi/artist/unsub',
    ]);
    expect(seen.first.bodyFields.keys, unorderedEquals(['params', 'encSecKey']));
  });

  test('artist detail reads whether the artist is followed', () async {
    final api = _api({
      '/api/v1/artist/12': {
        'code': 200,
        'artist': {'id': 12, 'name': '歌手', 'followed': true},
        'hotSongs': <Object>[],
      },
    });
    expect((await api.artistDetail('12')).artist.followed, isTrue);
  });

  test('risk-control errors include the dialog reason', () async {
    final api = NeteaseApi(
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'code': 250,
              'message': '关注异常',
              'dialog': {'subtitle': '您操作太快啦，请稍后再试'},
            }),
          ),
          200,
        ),
      ),
    );
    await expectLater(
      api.setFollowed(42, true),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', '关注异常：您操作太快啦，请稍后再试')),
    );
  });

  test('the follow feed reads its list from `event`', () async {
    final api = _api({
      '/api/v1/event/get': {
        'code': 200,
        'more': false,
        'lasttime': 5,
        'event': [
          {
            'id': 1,
            'type': 35,
            'eventTime': 1,
            'user': _user(2),
            'json': jsonEncode({'msg': '动态'}),
          },
        ],
      },
    });
    expect((await api.followFeed()).events.single.text, '动态');
  });

  test('follows and fans lists', () async {
    final api = _api({
      '/api/user/getfollows/1': {
        'code': 200,
        'more': true,
        'follow': [
          {..._user(2), 'followed': true, 'signature': ' 签名 '},
        ],
      },
      '/eapi/user/getfolloweds/1': {
        'code': 200,
        'more': false,
        'followeds': [_user(3, userType: 2)],
      },
    });
    final follows = await api.userFollows(1);
    expect(follows.more, isTrue);
    expect(follows.users.single.followed, isTrue);
    expect(follows.users.single.signature, '签名');
    final fans = await api.userFolloweds(1);
    expect(fans.users.single.musician, isTrue);
  });

  test('conversations show a preview of the last message', () async {
    final api = _api({
      '/api/msg/private/users': {
        'code': 200,
        'more': false,
        'msgs': [
          {
            'fromUser': _user(5),
            'lastMsg': jsonEncode({'msg': '在吗'}),
            'lastMsgTime': 1700000000000,
            'newMsgCount': 2,
          },
          {
            'fromUser': _user(6),
            'lastMsg': jsonEncode({
              'msg': '',
              'song': {'id': 1, 'name': '某首歌'},
            }),
            'lastMsgTime': 1700000000000,
          },
        ],
      },
    });
    final page = await api.conversations();
    expect(page.items.first.preview, '在吗');
    expect(page.items.first.unread, 2);
    expect(page.items.last.preview, '[歌曲] 某首歌');
  });

  test('message history is sorted old to new and pages by time', () async {
    final seen = <http.Request>[];
    final api = _api({
      '/weapi/msg/private/history': {
        'code': 200,
        'more': true,
        'msgs': [
          {
            'id': 2,
            'time': 2000,
            'fromUser': _user(1),
            'msg': jsonEncode({'msg': '后'}),
          },
          {
            'id': 1,
            'time': 1000,
            'fromUser': _user(9),
            'msg': jsonEncode({
              'msg': '',
              'picInfo': {'picUrl': 'http://p1.music.126.net/i.jpg'},
            }),
          },
        ],
      },
    }, seen: seen);
    final h = await api.messageHistory(9, before: DateTime.fromMillisecondsSinceEpoch(5000));
    // 走网页端 WEAPI（会顺带标成已读），参数是加密的。
    expect(seen.single.url.path, '/weapi/msg/private/history');
    expect(seen.single.bodyFields.keys, containsAll(['params', 'encSecKey']));
    expect(h.more, isTrue);
    expect([for (final m in h.messages) m.id], [1, 2]);
    expect(h.messages.first.imageUrl, 'https://p1.music.126.net/i.jpg');
    expect(h.messages.last.text, '后');
    expect(h.messages.last.fromUserId, 1);
  });

  test('message history falls back to the plain API when WEAPI fails', () async {
    final seen = <http.Request>[];
    final api = NeteaseApi(
      cookies: const {'MUSIC_U': 'u'},
      client: MockClient((r) async {
        seen.add(r);
        if (r.url.path.startsWith('/weapi/')) return http.Response('busy', 503);
        return http.Response(
          jsonEncode({
            'code': 200,
            'more': false,
            'msgs': [
              {
                'id': 1,
                'time': 1000,
                'fromUser': _user(9),
                'msg': jsonEncode({'msg': '在'}),
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final h = await api.messageHistory(9);
    expect(
      [for (final r in seen) r.url.path],
      ['/weapi/msg/private/history', '/api/msg/private/history'],
    );
    expect(seen.last.bodyFields['userId'], '9');
    expect(h.messages.single.text, '在');
  });

  test('sending a message goes through EAPI', () async {
    final seen = <http.Request>[];
    final api = _api({}, seen: seen);
    await api.sendMessage(9, 'hi');
    expect(seen.single.url.path, '/eapi/msg/private/send');
  });

  test('liking an event uses its thread id', () async {
    final seen = <http.Request>[];
    final api = _api({}, seen: seen);
    await api.likeEvent('A_EV_2_1_10', true);
    await api.likeEvent('A_EV_2_1_10', false);
    // 和 api-enhanced 一样走网页端 WEAPI。
    expect(seen.map((r) => r.url.path), ['/weapi/resource/like', '/weapi/resource/unlike']);
    expect(seen.first.bodyFields.keys, containsAll(['params', 'encSecKey']));
  });
}
