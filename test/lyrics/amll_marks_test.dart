import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/lyrics/ttml_parser.dart';
import 'package:netease_client/pages/now_playing/lyrics_view.dart';

Lyrics _parse(String body) => TtmlParser.parse(
  '<tt xmlns:itunes="x" xmlns:amll="y"><body>$body</body></tt>',
  source: LyricSource.amll,
);

LyricLine _line(int startSec, int endSec) => LyricLine(
  start: Duration(seconds: startSec),
  end: Duration(seconds: endSec),
  words: [LyricWord('a', Duration(seconds: startSec), Duration(seconds: endSec))],
);

void main() {
  group('AMLL 标记', () {
    test('amll:obscene 和 amll:empty-beat 挂到字上', () {
      final l = _parse(
        '<div><p begin="1" end="3">'
        '<span begin="1" end="2" amll:obscene="true">shit</span> '
        '<span begin="2" end="3" amll:empty-beat="2">ok</span>'
        '</p></div>',
      );
      final words = l.lines.single.words;
      expect(words[0].obscene, isTrue);
      expect(words[0].emptyBeat, 0);
      expect(words[1].obscene, isFalse);
      expect(words[1].emptyBeat, 2);
    });

    test('itunes:songPart 标到行上，旧写法 song-part 也认', () {
      final l = _parse(
        '<div itunes:songPart="Verse"><p begin="1" end="2"><span begin="1" end="2">a</span></p></div>'
        '<div itunes:song-part="Chorus"><p begin="3" end="4"><span begin="3" end="4">b</span></p></div>'
        '<p begin="5" end="6"><span begin="5" end="6">c</span></p>',
      );
      expect(l.lines.map((x) => x.songPart), ['Verse', 'Chorus', null]);
    });

    test('屏蔽不雅用语：全部屏蔽和保留首尾，空格保留', () {
      const w = LyricWord('shit ', Duration.zero, Duration.zero, obscene: true);
      expect(w.display(ObsceneMask.off), 'shit ');
      expect(w.display(ObsceneMask.full), '**** ');
      expect(w.display(ObsceneMask.partial), 's**t ');
      const clean = LyricWord('ok', Duration.zero, Duration.zero);
      expect(clean.display(ObsceneMask.full), 'ok');
    });

    test('缓存 JSON 保留三个标记', () {
      final l = _parse(
        '<div itunes:songPart="Bridge"><p begin="1" end="2">'
        '<span begin="1" end="2" amll:obscene="true" amll:empty-beat="3">x</span>'
        '</p></div>',
      );
      final back = Lyrics.fromJson(l.toJson())!;
      final line = back.lines.single;
      expect(line.songPart, 'Bridge');
      expect(line.words.single.obscene, isTrue);
      expect(line.words.single.emptyBeat, 3);
    });
  });

  group('间奏点', () {
    test('前奏和间隔够长的地方算间奏，短的不算', () {
      final lyrics = Lyrics(
        lines: [_line(6, 10), _line(12, 14), _line(25, 30)],
        source: LyricSource.amll,
        wordSynced: true,
      );
      final x = lyricInterludes(lyrics);
      expect(x.map((e) => (e.after, e.start.inSeconds, e.end.inSeconds)), [
        (-1, 0, 6),
        (1, 14, 25),
      ]);
    });

    test('重叠的行按最晚的结束时间算', () {
      final lyrics = Lyrics(
        lines: [_line(0, 20), _line(2, 4), _line(22, 25)],
        source: LyricSource.amll,
        wordSynced: true,
      );
      expect(lyricInterludes(lyrics), isEmpty);
    });

    test('三个点均匀消失：剩三份三个点，剩两份两个点，剩一份一个点', () {
      const start = Duration.zero, end = Duration(seconds: 3);
      int visible(double sec) => [
        for (var k = 0; k < 3; k++)
          if (InterludeDotsPainter.opacityAt(
                k,
                Duration(milliseconds: (sec * 1000).round()),
                start,
                end,
              ) >
              0)
            k,
      ].length;
      expect(visible(0), 3);
      expect(visible(0.5), 3);
      expect(visible(1.5), 2);
      expect(visible(2.5), 1);
      expect(visible(3), 0);
    });
  });
}
