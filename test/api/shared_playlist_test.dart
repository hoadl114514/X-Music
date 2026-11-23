import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/api/netease_api.dart';

void main() {
  test('specialType 300 marks a shared playlist even before anyone joins', () async {
    // 字段取自真实账号的共享歌单（刚创建，还没有成员）。
    final api = NeteaseApi(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 200,
            'playlist': [
              {'id': 1, 'name': 'test', 'specialType': 300, 'privacy': 0, 'sharedUsers': null},
              {'id': 2, 'name': '普通', 'specialType': 0, 'privacy': 10, 'sharedUsers': null},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final lists = await api.userPlaylists(1);
    expect(lists.first.shared, isTrue);
    expect(lists.first.sharedUsers, isEmpty);
    expect(lists.last.shared, isFalse);
  });

  test('shared playlist info maps each track to the member who added it', () {
    // 结构取自真实共享歌单的详情：trackIds 里的 uid 是添加人。
    final info = NeteaseApi.parseSharedPlaylistInfo({
      'code': 200,
      'playlist': {
        'id': 7,
        'creator': {'userId': 1, 'nickname': '我', 'avatarUrl': 'http://p1.music.126.net/a.jpg'},
        'sharedUsers': [
          {'userId': 2, 'nickname': '朋友', 'avatarUrl': 'http://p1.music.126.net/b.jpg'},
        ],
        'trackIds': [
          {'id': 100, 'uid': 2},
          {'id': 101, 'uid': 1},
          {'id': 102, 'uid': 999},
          {'id': 103},
        ],
      },
      'sharedPrivilege': {'status': 'SHARED', 'usePermission': 'NORMAL'},
    });
    expect(info.members.map((m) => m.nickname), ['我', '朋友']);
    expect(info.adders['100']?.nickname, '朋友');
    expect(info.adders['101']?.nickname, '我');
    expect(info.adders['101']?.avatarUrl, 'https://p1.music.126.net/a.jpg');
    // 已经退出的成员、没有 uid 的歌不显示添加人。
    expect(info.adders.containsKey('102'), isFalse);
    expect(info.adders.containsKey('103'), isFalse);
  });

  test('removing a contributor fails when the server says data false', () async {
    var reply = <String, Object>{'code': 200, 'data': false, 'message': ''};
    final paths = <String>[];
    final api = NeteaseApi(
      client: MockClient((r) async {
        paths.add(r.url.path);
        return http.Response(jsonEncode(reply), 200);
      }),
    );
    await expectLater(api.removeSharedContributor('7', 2), throwsA(isA<ApiException>()));
    reply = {'code': 200, 'data': true, 'message': ''};
    await api.removeSharedContributor('7', 2);
    expect(paths, everyElement('/eapi/playlist/shared/contributor/delete'));
  });
}
