import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/api/netease_api.dart';

/// 按路径后缀返回假数据，并记下所有请求。
NeteaseApi _api(Map<String, Object> routes, List<http.Request> seen) => NeteaseApi(
  cookies: const {'MUSIC_U': 'u', '__csrf': 'c'},
  client: MockClient((r) async {
    seen.add(r);
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

void main() {
  test('createPlaylist posts to weapi and parses the new playlist', () async {
    final seen = <http.Request>[];
    final api = _api({
      '/weapi/playlist/create': {
        'code': 200,
        'playlist': {
          'id': 42,
          'name': '新歌单',
          'creator': {'userId': 1, 'nickname': '我'},
        },
      },
    }, seen);
    final p = await api.createPlaylist('新歌单', private: true);
    expect(p?.id, '42');
    expect(p?.name, '新歌单');
    expect(seen.single.url.toString(), 'https://music.163.com/weapi/playlist/create');
  });

  test('deletePlaylist, rename and description use the expected endpoints', () async {
    final seen = <http.Request>[];
    final api = _api(const {}, seen);
    await api.deletePlaylist('42');
    await api.renamePlaylist('42', '改名');
    await api.setPlaylistDescription('42', '简介');
    expect(
      [for (final r in seen) r.url.path],
      ['/weapi/playlist/remove', '/eapi/playlist/update/name', '/eapi/playlist/desc/update'],
    );
  });

  test('setPlaylistCover uploads the image to NOS, then sets the cover id', () async {
    final seen = <http.Request>[];
    final api = _api({
      '/weapi/nos/token/alloc': {
        'code': 200,
        'result': {'objectKey': 'obj/key.png', 'token': 'tok', 'docId': 9001},
      },
    }, seen);
    final png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 1, 2, 3];
    final url = await api.setPlaylistCover('42', png);
    expect(url, 'https://p1.music.126.net/obj/key.png');
    expect(
      [for (final r in seen) r.url.path],
      ['/weapi/nos/token/alloc', '/yyimgs/obj/key.png', '/weapi/playlist/cover/update'],
    );
    final upload = seen[1];
    expect(upload.url.host, 'nosup-hz1.127.net');
    expect(upload.headers['x-nos-token'], 'tok');
    expect(upload.headers['Content-Type'], startsWith('image/png'));
    expect(upload.bodyBytes, png);
  });

  test('uploadImage reports a missing token', () async {
    final api = _api({
      '/weapi/nos/token/alloc': {'code': 200, 'result': <String, Object>{}},
    }, []);
    expect(api.uploadImage([1, 2, 3]), throwsA(isA<ApiException>()));
  });

  test('shareEvent sends type, msg and id to the share endpoint', () async {
    final seen = <http.Request>[];
    final api = _api(const {}, seen);
    await api.shareEvent('好听', type: ShareType.song, id: '5');
    await api.shareEvent('只有文字');
    expect(seen[0].url.toString(), 'https://music.163.com/api/share/friends/resource');
    expect(seen[0].bodyFields, {'type': 'song', 'msg': '好听', 'id': '5'});
    expect(seen[1].bodyFields, {'type': 'noresource', 'msg': '只有文字', 'id': ''});
  });

  test('shareEvent retries through weapi when the plain API refuses', () async {
    final seen = <http.Request>[];
    final api = _api({
      '/api/share/friends/resource': {'code': 400, 'message': '参数错误'},
      '/weapi/share/friends/resource': {'code': 200},
    }, seen);
    await api.shareEvent('hi', type: ShareType.playlist, id: '42');
    expect(
      [for (final r in seen) r.url.path],
      ['/api/share/friends/resource', '/weapi/share/friends/resource'],
    );
  });

  test('shareEvent does not retry when login is required', () async {
    final seen = <http.Request>[];
    final api = _api({
      '/api/share/friends/resource': {'code': 301},
    }, seen);
    await expectLater(api.shareEvent('hi'), throwsA(isA<ApiException>()));
    expect(seen, hasLength(1));
  });
}
