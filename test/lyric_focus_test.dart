import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/pages/now_playing/lyrics_view.dart';

LyricLine _line(int start, int end) => LyricLine(
  start: Duration(seconds: start),
  end: Duration(seconds: end),
  words: [LyricWord('x', Duration(seconds: start), Duration(seconds: end))],
);

Lyrics _lyrics(List<LyricLine> lines, {bool wordSynced = true}) =>
    Lyrics(lines: lines, source: LyricSource.amll, wordSynced: wordSynced);

void main() {
  // 第 0 行 0–6 秒；第 1 行 4 秒就开始（重叠）；第 2 行 8 秒开始。
  final overlap = _lyrics([_line(0, 6), _line(4, 7), _line(8, 9)]);

  test('上一句没唱完时停在上一句', () {
    expect(lyricFocusIndex(overlap, 1, const Duration(seconds: 5)), 0);
  });

  test('上一句唱完后滚到下一句', () {
    expect(lyricFocusIndex(overlap, 1, const Duration(seconds: 6)), 1);
    expect(lyricFocusIndex(overlap, 2, const Duration(milliseconds: 8500)), 2);
  });

  test('逐行歌词不做重叠判断', () {
    final lrc = _lyrics([_line(0, 6), _line(4, 7)], wordSynced: false);
    expect(lyricFocusIndex(lrc, 1, const Duration(seconds: 5)), 1);
  });

  test('还没开始时保持 -1', () {
    expect(lyricFocusIndex(overlap, -1, Duration.zero), -1);
  });
}
