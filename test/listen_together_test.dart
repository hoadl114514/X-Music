import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/state/listen_together.dart';

import 'support/fakes.dart';

void main() {
  test('parseLink reads room and inviter from a share text', () {
    final r = ListenTogether.parseLink(
      '来和我一起听歌吧：https://st.music.163.com/listen-together/share/?songId=1&roomId=abc&inviterId=42',
    );
    expect(r?.roomId, 'abc');
    expect(r?.inviterId, '42');
    expect(ListenTogether.parseLink('https://music.163.com/#/song?id=1'), isNull);
    expect(ListenTogether.parseLink('随便一段话'), isNull);
  });

  test('creating a room reports the queue and the current song, leaving ends it', () async {
    final paths = <String>[];
    final client = MockClient((req) async {
      paths.add(req.url.path);
      final body = switch (req.url.path) {
        '/api/nuser/account/get' => {
          'code': 200,
          'profile': {'userId': 7, 'nickname': '我'},
        },
        '/eapi/listen/together/room/create' => {
          'code': 200,
          'data': {
            'roomInfo': {'roomId': 'r1', 'creatorId': 7},
          },
        },
        '/eapi/listen/together/room/check' => {
          'code': 200,
          'data': {'joinable': true, 'status': 'AVAILABLE'},
        },
        '/weapi/listen/together/status/get' => {
          'code': 200,
          'data': {
            'inRoom': true,
            'roomInfo': {
              'roomId': 'r1',
              'roomUsers': [
                {'userId': 7, 'nickname': '我'},
              ],
            },
          },
        },
        _ => {'code': 200},
      };
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    });
    final f = await fakeServices(client: client);
    await f.services.account.loginWithCookies({'MUSIC_U': 'x'});
    await f.services.player.playQueue([song('1'), song('2')], title: '测试');

    final listen = f.services.listen;
    await listen.createRoom();
    expect(listen.active, isTrue);
    expect(listen.isHost, isTrue);
    expect(listen.inviteLink, contains('roomId=r1'));
    expect(paths, contains('/eapi/listen/together/sync/list/command/report'));
    expect(paths, contains('/eapi/listen/together/play/command/report'));
    expect(paths, contains('/eapi/listen/together/heartbeat'));

    await listen.leave();
    expect(listen.active, isFalse);
    expect(paths, contains('/eapi/listen/together/end/v2'));
  });

  test('positionAt adds the time since the server took the command while playing', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1700000010000);
    ListenTogetherCommand cmd({required bool playing, int server = 1700000005000}) =>
        ListenTogetherCommand(
          songId: '1',
          playing: playing,
          progress: const Duration(seconds: 30),
          serverTime: server,
          clientSeq: 1,
          userId: 2,
        );
    expect(cmd(playing: true).positionAt(now, receivedAt: now), const Duration(seconds: 35));
    expect(cmd(playing: false).positionAt(now, receivedAt: now), const Duration(seconds: 30));
    // 服务器时间不像时间戳：从收到快照的时间算。
    expect(
      cmd(
        playing: true,
        server: 7,
      ).positionAt(now, receivedAt: now.subtract(const Duration(seconds: 2))),
      const Duration(seconds: 32),
    );
  });

  test('joining follows the room: its list, song, progress and play state', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final client = MockClient((req) async {
      final body = switch (req.url.path) {
        '/api/nuser/account/get' => {
          'code': 200,
          'profile': {'userId': 9, 'nickname': '我'},
        },
        '/eapi/listen/together/room/check' => {
          'code': 200,
          'data': {'joinable': true, 'status': 'AVAILABLE'},
        },
        '/eapi/listen/together/sync/playlist/get' => {
          'code': 200,
          'data': {
            'playlist': {
              'displayList': {
                'result': [11, 12, 13],
              },
            },
            'playCommand': {
              'userId': 7,
              'clientSeq': 5,
              'targetSongId': '12',
              'playStatus': 'PLAY',
              'progress': 30000,
              'serverSeq': now - 5000,
              'commandType': 'GOTO',
            },
          },
        },
        '/api/v3/song/detail' => {
          'code': 200,
          'songs': [
            for (final id in [11, 12, 13])
              {
                'id': id,
                'name': '歌$id',
                'ar': [
                  {'id': 1, 'name': '歌手'},
                ],
                'al': {'id': 1, 'name': '专辑'},
                'dt': 240000,
              },
          ],
        },
        _ => {'code': 200},
      };
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    });
    final f = await fakeServices(client: client);
    await f.services.account.loginWithCookies({'MUSIC_U': 'x'});
    final listen = f.services.listen;
    await listen.join(
      'https://st.music.163.com/listen-together/share/?songId=12&roomId=r1&inviterId=7',
    );
    final player = f.services.player;
    expect(listen.active, isTrue);
    expect(listen.isHost, isFalse);
    expect([for (final s in player.queue) s.id], ['11', '12', '13']);
    expect(player.current?.id, '12');
    expect(player.isPlaying, isTrue);
    // 30 秒 + 服务器收到指令后过去的约 5 秒。
    expect(player.position.inSeconds, inInclusiveRange(34, 37));
    await listen.leave();
  });

  test('a longer room list (host FM got more songs) does not restart the current song', () async {
    final f = await fakeServices();
    final player = f.services.player;
    await player.playQueue([song('1'), song('2')], title: '一起听');
    f.engine.advance(const Duration(seconds: 40));
    final loads = f.engine.loaded.length;
    await player.syncQueue([song('1'), song('2'), song('3'), song('4')], title: '一起听');
    expect(player.current?.id, '1');
    expect([for (final s in player.queue) s.id], ['1', '2', '3', '4']);
    expect(f.engine.loaded.length, loads, reason: '没有重新加载');
    expect(f.engine.position, const Duration(seconds: 40), reason: '没有跳回开头');
  });
}
