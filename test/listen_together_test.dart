import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
}
