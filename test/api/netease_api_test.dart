import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/api/cookies.dart';
import 'package:netease_client/api/netease_api.dart';
import 'package:netease_client/api/xeapi_crypto.dart';
import 'package:netease_client/data/models.dart';
import 'package:pointycastle/export.dart';

http.Response json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

final _xeapiStaticKey = Uint8List.fromList([
  for (var i = 0; i < 64; i += 2)
    int.parse(
      'ab1d5a430f6bb04a3f01e81ddd72bd916d5ce591248ac128714806d7f8fb1b84'.substring(i, i + 2),
      radix: 16,
    ),
]);

Uint8List _aes(List<int> key, List<int> data) =>
    (PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(AESEngine()))
          ..init(true, PaddedBlockCipherParameters(KeyParameter(Uint8List.fromList(key)), null)))
        .process(Uint8List.fromList(data));

/// 模拟 XEAPI 服务端：先应答公钥注册，其余请求交给 [handler]，返回值按 XEAPI 加密。
MockClient _xeapiClient(
  Map<String, Object?> Function(http.Request r) handler, {
  List<http.Request>? requests,
}) {
  final server = Uint8List.fromList(List.generate(32, (i) => i * 7 + 3));
  return MockClient((r) async {
    requests?.add(r);
    if (r.url.path == '/api/bsr/sk/get') {
      final f = r.bodyFields;
      expect(f['signature'], XeapiCrypto.sign(f['timestamp']!, f['nonce']!));
      final key = jsonEncode({
        'publicKey': base64.encode(X25519.publicKey(server)),
        'version': '3',
        'sk': 'sk1',
      });
      return json({
        'code': 200,
        'data': {
          'encryptedData': base64.encode(_aes(_xeapiStaticKey, utf8.encode(key))),
          'timestamp': 42,
          'signature': XeapiCrypto.sign('42', f['nonce']!),
        },
      });
    }
    final body = jsonEncode(handler(r));
    return http.Response.bytes(_aes(utf8.encode('e82ckenh8dichen8'), utf8.encode(body)), 200);
  });
}

void main() {
  test('parseCookie handles separators, blanks and "=" in values', () {
    expect(parseCookie(' MUSIC_U=ab=c ; __csrf=x\nbad; empty= ;=v'), {
      'MUSIC_U': 'ab=c',
      '__csrf': 'x',
    });
    expect(encodeCookie({'a': '1', 'b': '2'}), 'a=1; b=2');
  });

  test('requests carry device defaults plus the user cookie', () async {
    late http.Request seen;
    final api = NeteaseApi(
      client: MockClient((r) async {
        seen = r;
        return json({'code': 200, 'profile': null});
      }),
      cookies: {'MUSIC_U': 'secret', 'os': 'android'},
    );
    expect(await api.account(), isNull);
    final cookie = seen.headers['Cookie']!;
    expect(cookie, contains('MUSIC_U=secret'));
    expect(cookie, contains('os=android')); // 用户的同名字段优先。
    expect(cookie, contains('deviceId=pyncm!'));
  });

  test('searchSongs parses artists, album cover and alias', () async {
    final api = NeteaseApi(
      client: MockClient(
        (r) async => json({
          'code': 200,
          'result': {
            'songCount': 99,
            'songs': [
              {
                'id': 5,
                'name': '歌',
                'ar': [
                  {'name': 'A'},
                  {'name': 'B'},
                ],
                'al': {'name': '专辑', 'picUrl': 'http://p1.music.126.net/x.jpg'},
                'dt': 1234,
                'tns': ['Song'],
              },
            ],
          },
        }),
      ),
    );
    final r = await api.searchSongs('歌');
    expect(r.total, 99);
    final s = r.songs.single;
    expect((s.id, s.title, s.artist, s.album, s.subtitle), ('5', '歌', 'A / B', '专辑', 'Song'));
    expect(s.duration, const Duration(milliseconds: 1234));
    expect(s.coverUrl, 'https://p1.music.126.net/x.jpg');
  });

  test('qualities lists only the levels the track has, low to high', () async {
    final api = NeteaseApi(
      client: MockClient(
        (r) async => json({
          'code': 200,
          'data': {
            'l': {'br': 128000, 'size': 1, 'sr': 44100},
            'h': {'br': 320000, 'size': 2, 'sr': 44100},
            'sq': {'br': 900000, 'size': 3, 'sr': 48000},
            'hr': null,
            'db': null,
            'jm': {'br': 5000000, 'size': 4, 'sr': 192000},
            'vi': {'br': 1, 'size': 1},
          },
        }),
      ),
    );
    final qs = await api.qualities('1');
    expect(qs.map((q) => q.quality), [
      AudioQuality.standard,
      AudioQuality.exhigh,
      AudioQuality.lossless,
      AudioQuality.jymaster,
    ]);
    expect(qs[2].sampleRate, 48000);
  });

  test('songUrl goes through XEAPI with a registered public key', () async {
    final requests = <http.Request>[];
    final api = NeteaseApi(
      cookies: {'MUSIC_U': 'u'},
      client: _xeapiClient((r) {
        expect(
          r.url.toString(),
          'https://interface3.music.163.com/xeapi/song/enhance/player/url/v1',
        );
        expect(r.headers['x-music-u'], 'u');
        expect(r.bodyFields.keys, ['C', 'S', 'R']);
        return {
          'code': 200,
          'data': [
            {'url': 'http://m801.music.126.net/x.flac', 'level': 'hires'},
          ],
        };
      }, requests: requests),
    );
    final u = await api.songUrl('1', AudioQuality.hires);
    expect(u!.quality, AudioQuality.hires);
    expect(u.url, 'http://m801.music.126.net/x.flac');
    // 公钥只取一次。
    await api.songUrl('2', AudioQuality.hires);
    expect(requests.where((r) => r.url.path == '/api/bsr/sk/get'), hasLength(1));
  });

  test('songUrl reads level / trial; null url means unavailable', () async {
    var call = 0;
    final api = NeteaseApi(
      client: _xeapiClient(
        (r) => call++ == 0
            ? {
                'code': 200,
                'data': [
                  {
                    'url': 'http://m701.music.126.net/a.flac',
                    'level': 'exhigh',
                    'freeTrialInfo': {'start': 30000, 'end': 60000},
                  },
                ],
              }
            : {
                'code': 200,
                'data': [
                  {'url': null, 'code': 404},
                ],
              },
      ),
    );
    final u = await api.songUrl('1', AudioQuality.lossless);
    expect(u!.quality, AudioQuality.exhigh);
    expect(u.trial, (start: const Duration(seconds: 30), end: const Duration(seconds: 60)));
    expect(await api.songUrl('1', AudioQuality.standard), isNull);
  });

  test('songUrl does not fall back to EAPI when XEAPI fails', () async {
    final paths = <String>[];
    final api = NeteaseApi(
      client: MockClient((r) async {
        paths.add(r.url.path);
        return json({'code': 500});
      }),
    );
    await expectLater(api.songUrl('1', AudioQuality.lossless), throwsA(isA<ApiException>()));
    expect(paths, ['/api/bsr/sk/get']);
  });

  /// XEAPI 服务端 + 易盾 token 接口。
  MockClient shareClient(
    Map<String, Object?> Function(http.Request r) xeapi, {
    List<http.Request>? requests,
    Map<String, Object?> plain = const {'code': 200},
  }) {
    final x = _xeapiClient(xeapi, requests: requests);
    return MockClient((r) async {
      if (r.url.host == 'ac.dun.163yun.com') {
        requests?.add(r);
        return http.Response('null([200,1794818402190,"tok123"])', 200);
      }
      if (r.url.host == 'music.163.com') {
        requests?.add(r);
        return json(plain);
      }
      final copy = http.Request(r.method, r.url)
        ..headers.addAll(r.headers)
        ..bodyBytes = r.bodyBytes;
      return http.Response.fromStream(await x.send(copy));
    });
  }

  test('shareEvent goes through XEAPI with an anti-cheat token', () async {
    final requests = <http.Request>[];
    final api = NeteaseApi(
      cookies: {'MUSIC_U': 'u'},
      client: shareClient((r) {
        expect(r.url.toString(), 'https://interface3.music.163.com/xeapi/share/friends/resource');
        expect(r.headers['X-antiCheatToken'], 'tok123');
        return {'code': 200};
      }, requests: requests),
    );
    await api.shareEvent('好听', type: ShareType.song, id: '5');
    expect(requests.where((r) => r.url.host == 'music.163.com'), isEmpty);
  });

  test('shareEvent falls back to the plain API and reports the XEAPI error', () async {
    final requests = <http.Request>[];
    final api = NeteaseApi(
      cookies: {'MUSIC_U': 'u'},
      client: shareClient(
        (r) => {'code': 400, 'message': '当前版本不支持分享歌曲'},
        requests: requests,
        plain: {'code': 400, 'message': '其他错误'},
      ),
    );
    await expectLater(
      api.shareEvent('hi', type: ShareType.song, id: '5'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', '当前版本不支持分享歌曲')),
    );
    final plain = requests.where((r) => r.url.host == 'music.163.com').single;
    expect(plain.bodyFields, {'type': 'song', 'msg': 'hi', 'id': '5'});
  });

  test('shareEvent succeeds when the plain API accepts it', () async {
    final api = NeteaseApi(cookies: {'MUSIC_U': 'u'}, client: shareClient((r) => {'code': 400}));
    await api.shareEvent('只有文字');
  });

  test('shareEvent does not retry when login is required', () async {
    final requests = <http.Request>[];
    final api = NeteaseApi(client: shareClient((r) => {'code': 301}, requests: requests));
    await expectLater(api.shareEvent('hi'), throwsA(isA<ApiException>()));
    expect(requests.where((r) => r.url.host == 'music.163.com'), isEmpty);
  });

  test('non-200 codes become ApiException; 301 means login needed', () async {
    final api = NeteaseApi(client: MockClient((r) async => json({'code': 301, 'msg': '需要登录'})));
    await expectLater(
      api.userPlaylists(1),
      throwsA(
        isA<ApiException>()
            .having((e) => e.needsLogin, 'needsLogin', isTrue)
            .having((e) => e.message, 'message', '需要登录'),
      ),
    );
  });

  test('network and HTTP failures become ApiException', () async {
    final api = NeteaseApi(client: MockClient((r) async => http.Response('oops', 503)));
    await expectLater(api.searchSongs('x'), throwsA(isA<ApiException>()));
    final api2 = NeteaseApi(client: MockClient((r) async => throw http.ClientException('offline')));
    await expectLater(api2.searchSongs('x'), throwsA(isA<ApiException>()));
  });
}
