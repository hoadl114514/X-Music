import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/api/netease_api.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/lyrics/amll_lyrics.dart';
import 'package:netease_client/lyrics/lyric_service.dart';
import 'package:netease_client/lyrics/qq_lyrics.dart';

class _Netease extends NeteaseApi {
  _Netease(this.texts);

  final Map<String, String> texts;
  var calls = 0;

  @override
  Future<Map<String, String>> lyricTexts(String songId) async {
    calls++;
    return {
      for (final k in const ['lrc', 'yrc', 'tlyric', 'romalrc', 'ytlrc', 'yromalrc'])
        k: texts[k] ?? '',
    };
  }
}

const _song = Song(id: '42', title: 't', artist: 'a', album: '', duration: Duration(minutes: 3));

LyricService _service(_Netease netease, String ttml) => LyricService(
  netease: netease,
  qq: QqLyrics(client: MockClient((_) async => http.Response('', 500))),
  amll: AmllLyrics(client: MockClient((_) async => http.Response.bytes(utf8.encode(ttml), 200))),
);

void main() {
  test('AMLL 没有罗马音时从网易云拉取，按时间对应到行', () async {
    final netease = _Netease({
      'lrc': '[00:01.00]星\n[00:05.00]空',
      'romalrc': '[00:01.10]hoshi\n[00:05.20]sora',
    });
    const ttml =
        '<tt><body><div>'
        '<p begin="1" end="2"><span begin="1" end="2">星</span></p>'
        '<p begin="5" end="6"><span begin="5" end="6">空</span></p>'
        '</div></body></tt>';
    final l = await _service(netease, ttml).fetch(_song, LyricSource.amll, fallback: false);
    expect(l.source, LyricSource.amll);
    expect(l.lines.map((x) => x.romaji), ['hoshi', 'sora']);
  });

  test('AMLL 自带罗马音时不请求网易云', () async {
    final netease = _Netease({'lrc': '[00:01.00]星', 'romalrc': '[00:01.00]other'});
    const ttml =
        '<tt><body><div><p begin="1" end="2"><span begin="1" end="2">星</span>'
        '<span ttm:role="x-roman">hoshi</span></p></div></body></tt>';
    final l = await _service(netease, ttml).fetch(_song, LyricSource.amll, fallback: false);
    expect(l.lines.single.romaji, 'hoshi');
    expect(netease.calls, 0);
  });

  test('网易云也没有罗马音时保持原样', () async {
    final netease = _Netease({'lrc': '[00:01.00]星'});
    const ttml =
        '<tt><body><div><p begin="1" end="2"><span begin="1" end="2">星</span></p></div></body></tt>';
    final l = await _service(netease, ttml).fetch(_song, LyricSource.amll, fallback: false);
    expect(l.lines.single.romaji, isNull);
    expect(l.lines.single.text, '星');
  });

  test('按给定顺序换源：AMLL 没有时换到下一个', () async {
    final netease = _Netease({'lrc': '[00:01.00]网易云'});
    final service = LyricService(
      netease: netease,
      qq: QqLyrics(client: MockClient((_) async => http.Response('', 500))),
      amll: AmllLyrics(client: MockClient((_) async => http.Response('lyric not found', 404))),
    );
    final l = await service.fetch(
      _song,
      LyricSource.amll,
      order: [LyricSource.amll, LyricSource.netease, LyricSource.qq],
    );
    expect(l.source, LyricSource.netease);
    expect(l.lines.single.text, '网易云');
  });

  test('AMLL 出错（如超时、服务异常）时同样换到下一个', () async {
    final netease = _Netease({'lrc': '[00:01.00]网易云'});
    final service = LyricService(
      netease: netease,
      qq: QqLyrics(client: MockClient((_) async => http.Response('', 500))),
      amll: AmllLyrics(client: MockClient((_) async => http.Response('oops', 502))),
    );
    final l = await service.fetch(
      _song,
      LyricSource.amll,
      order: [LyricSource.amll, LyricSource.netease],
    );
    expect(l.source, LyricSource.netease);
  });

  test('前面的来源卡住时，后面的来源已经同时在取，不用排队等', () async {
    final netease = _Netease({'lrc': '[00:01.00]网易云'});
    final hang = Completer<http.Response>();
    final service = LyricService(
      netease: netease,
      qq: QqLyrics(client: MockClient((_) async => http.Response('', 500))),
      amll: AmllLyrics(client: MockClient((_) => hang.future)),
    );
    final result = service.fetch(
      _song,
      LyricSource.amll,
      order: [LyricSource.amll, LyricSource.netease],
    );
    // 网易云已经同时发出请求，不用等 AMLL 回来。
    await pumpEventQueue();
    expect(netease.calls, 1);
    hang.complete(http.Response('lyric not found', 404));
    final l = await result;
    expect(l.source, LyricSource.netease);
  });

  test('AMLL 取罗马音和网易云换源共用同一个请求', () async {
    final netease = _Netease({'lrc': '[00:01.00]星', 'romalrc': '[00:01.00]hoshi'});
    const ttml =
        '<tt><body><div><p begin="1" end="2"><span begin="1" end="2">星</span></p></div></body></tt>';
    final l = await _service(
      netease,
      ttml,
    ).fetch(_song, LyricSource.amll, order: [LyricSource.amll, LyricSource.netease]);
    expect(l.source, LyricSource.amll);
    expect(l.lines.single.romaji, 'hoshi');
    expect(netease.calls, 1);
  });

  test('自动换源顺序：网易云 → AMLL → QQ', () {
    expect(LyricService.fallbackOrder, [LyricSource.netease, LyricSource.amll, LyricSource.qq]);
  });
}
