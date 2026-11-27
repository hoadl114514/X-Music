import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/lyrics/amll_lyrics.dart';
import 'package:netease_client/lyrics/ttml_parser.dart';

// 按 AMLL 库里真实 TTML 的写法截取：词间空格是 span 外的文本，翻译、罗马音、背景人声是行内 span。
const _amll =
    '<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" '
    'xmlns:itunes="http://music.apple.com/lyric-ttml-internal" xmlns:amll="http://www.example.com/ns/amll">'
    '<head><metadata xmlns=""><ttm:agent type="person" xml:id="v1"/>'
    '<amll:meta key="ncmMusicId" value="2744403189"/></metadata></head>'
    '<body dur="3:55.000"><div begin="18.124" end="3:55.000">'
    '<p begin="18.124" end="21.793" itunes:key="L1" ttm:agent="v1">'
    '<span begin="18.124" end="18.357">&quot;Eat</span><span begin="18.357" end="18.599">ing</span> '
    '<span begin="18.599" end="18.791">out</span> <span begin="20.090" end="20.301">it&apos;s</span>'
    '<span ttm:role="x-translation" xml:lang="zh-CN">“吃垃圾” 它的</span></p>'
    '<p begin="1:03.195" end="1:10.010" itunes:key="L2" ttm:agent="v2">'
    '<span begin="1:03.204" end="1:03.690">星</span><span begin="1:03.690" end="1:04.160">空</span>'
    '<span ttm:role="x-roman">hoshizora</span>'
    '<span ttm:role="x-bg" begin="1:03.195" end="1:06.050"><span begin="1:03.195" end="1:03.513">(見)</span>'
    '<span ttm:role="x-translation" xml:lang="zh-Hans">背景</span></span></p>'
    '</div></body></tt>';

void main() {
  group('TtmlParser.parseTime', () {
    test('各种写法', () {
      expect(TtmlParser.parseTime('28.571'), 28571);
      expect(TtmlParser.parseTime('5:16.277'), 316277);
      expect(TtmlParser.parseTime('00:29.231'), 29231);
      expect(TtmlParser.parseTime('1:00:01.5'), 3601500);
      expect(TtmlParser.parseTime('12.3s'), 12300);
      expect(TtmlParser.parseTime('450ms'), 450);
      expect(TtmlParser.parseTime(''), isNull);
      expect(TtmlParser.parseTime('abc'), isNull);
      expect(TtmlParser.parseTime('1:2:3:4'), isNull);
    });
  });

  group('TtmlParser.parse', () {
    test('AMLL 逐字歌词：词间空格、实体、翻译、罗马音；丢弃背景人声', () {
      final l = TtmlParser.parse(_amll, source: LyricSource.amll);
      expect(l.source, LyricSource.amll);
      expect(l.wordSynced, isTrue);
      expect(l.lines, hasLength(2));

      final first = l.lines[0];
      expect(first.text, '"Eating out it\'s');
      expect(first.words.map((w) => w.text), ['"Eat', 'ing ', 'out ', "it's"]);
      expect(first.words.first.start, const Duration(milliseconds: 18124));
      expect(first.words.last.end, const Duration(milliseconds: 20301));
      expect(first.start, const Duration(milliseconds: 18124));
      expect(first.end, const Duration(milliseconds: 21793));
      expect(first.translation, '“吃垃圾” 它的');
      expect(first.romaji, isNull);

      final second = l.lines[1];
      expect(second.text, '星空');
      expect(second.romaji, 'hoshizora');
      expect(second.translation, isNull);
      expect(second.start, const Duration(milliseconds: 63195));
    });

    test('逐行 TTML 和 head 里的 Apple 式翻译', () {
      const ttml = '''<?xml version="1.0" encoding="UTF-8"?>
<!-- comment -->
<tt xmlns="http://www.w3.org/ns/ttml" xmlns:itunes="http://music.apple.com/lyric-ttml-internal" itunes:timing="Line">
  <head>
    <metadata>
      <iTunesMetadata xmlns="http://music.apple.com/lyric-ttml-internal">
        <translations>
          <translation type="subtitle" xml:lang="zh-Hans">
            <text for="L1">你好</text>
          </translation>
        </translations>
        <transliterations>
          <transliteration xml:lang="ja-Latn"><text for="L2">sekai</text></transliteration>
        </transliterations>
      </iTunesMetadata>
    </metadata>
  </head>
  <body>
    <div>
      <p begin="00:05.000" end="00:08.000" itunes:key="L1">Hello  there</p>
      <p begin="00:09.000" itunes:key="L2">世界</p>
      <p begin="00:12.000" end="00:13.000"></p>
    </div>
  </body>
</tt>''';
      final l = TtmlParser.parse(
        ttml,
        source: LyricSource.amll,
        duration: const Duration(seconds: 20),
      );
      expect(l.wordSynced, isFalse);
      expect(l.lines.map((x) => x.text), ['Hello there', '世界']);
      expect(l.lines[0].translation, '你好');
      expect(l.lines[0].words.single.end, const Duration(seconds: 8));
      expect(l.lines[1].romaji, 'sekai');
      // 没有 end 时延到歌曲结束。
      expect(l.lines[1].end, const Duration(seconds: 20));
    });

    test('排版缩进不算词间空格', () {
      const ttml = '''<tt><body><div>
  <p begin="1" end="3">
    <span begin="1" end="2">你</span>
    <span begin="2" end="3">好</span>
  </p>
</div></body></tt>''';
      final l = TtmlParser.parse(ttml, source: LyricSource.amll);
      expect(l.lines.single.text, '你好');
      expect(l.lines.single.words, hasLength(2));
    });

    test('行按时间排序，超出歌曲时长的行丢弃', () {
      const ttml =
          '<tt><body><div>'
          '<p begin="10" end="11"><span begin="10" end="11">B</span></p>'
          '<p begin="2" end="3"><span begin="2" end="3">A</span></p>'
          '<p begin="40" end="41"><span begin="40" end="41">C</span></p>'
          '</div></body></tt>';
      final l = TtmlParser.parse(
        ttml,
        source: LyricSource.amll,
        duration: const Duration(seconds: 30),
      );
      expect(l.lines.map((x) => x.text), ['A', 'B']);
    });

    test('坏输入返回空歌词，不抛异常', () {
      for (final bad in ['', 'not xml', '<tt><body><p begin="1"', '<tt><head/></tt>', '<']) {
        expect(TtmlParser.parse(bad, source: LyricSource.amll).isEmpty, isTrue, reason: bad);
      }
    });
  });

  group('AmllLyrics', () {
    const song = Song(
      id: '2744403189',
      title: 'Opalite',
      artist: 'Taylor Swift',
      album: '',
      duration: Duration(minutes: 4),
    );

    test('按网易云 id 请求并按 UTF-8 解码', () async {
      late Uri url;
      final client = MockClient((req) async {
        url = req.url;
        // 真实接口返回 text/plain 不带 charset。
        return http.Response.bytes(
          utf8.encode(_amll),
          200,
          headers: {'content-type': 'text/plain'},
        );
      });
      final l = await AmllLyrics(client: client).fetch(song);
      expect(
        url.toString(),
        'https://api.beta.amllhub.bikonoo.com/api/v1/lyrics/ncm-lyrics/2744403189',
      );
      expect(l.source, LyricSource.amll);
      expect(l.lines.first.translation, '“吃垃圾” 它的');
    });

    test('404 返回空歌词，其他错误抛异常', () async {
      final notFound = MockClient((_) async => http.Response('lyric not found: 1', 404));
      expect((await AmllLyrics(client: notFound).fetch(song)).isEmpty, isTrue);
      final broken = MockClient((_) async => http.Response('oops', 502));
      await expectLater(
        AmllLyrics(client: broken).fetch(song),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('非网易云 id 不发请求', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response('', 200);
      });
      const local = Song(
        id: 'local:abc',
        title: '',
        artist: '',
        album: '',
        duration: Duration.zero,
      );
      expect((await AmllLyrics(client: client).fetch(local)).isEmpty, isTrue);
      expect(called, isFalse);
    });
  });
}
