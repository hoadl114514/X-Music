import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/pages/now_playing/karaoke_text.dart';

LyricWord _w(String t, int s, [String? ruby]) => LyricWord(
  t,
  Duration(milliseconds: s),
  Duration(milliseconds: s + 100),
  ruby: ruby,
);

Future<RenderKaraokeText> _pump(
  WidgetTester tester,
  List<LyricWord> words, {
  bool karaoke = false,
  double width = 160,
  TextAlign align = TextAlign.left,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: KaraokeText(
            words: words,
            style: const TextStyle(fontSize: 20, height: 1.25),
            color: Colors.white,
            karaoke: karaoke,
            position: const Duration(milliseconds: 250),
            textAlign: align,
          ),
        ),
      ),
    ),
  );
  return tester.renderObject<RenderKaraokeText>(find.byType(KaraokeText));
}

void main() {
  // 英文被拆成音节的词："Eat" + "ing"。
  final english = [
    for (final (i, t) in [
      'Eat',
      'ing ',
      'out ',
      'of ',
      'the ',
      'trash ',
      'nev',
      'er ',
      'last',
    ].indexed)
      _w(t, i * 100),
  ];

  testWidgets('拆成音节的英文词整词换行，不断在词中间', (tester) async {
    final r = await _pump(tester, english);
    final boxes = r.wordBoxes;
    expect(boxes.every((b) => b.length == 1), isTrue);
    // Eat|ing、nev|er 各在同一行。
    expect(boxes[0].single.top, boxes[1].single.top);
    expect(boxes[6].single.top, boxes[7].single.top);
    // 确实换行了。
    expect(boxes.last.single.top, greaterThan(boxes.first.single.top));
  });

  testWidgets('填色范围不越过相邻的行（hand 顶部被点亮的问题）', (tester) async {
    final r = await _pump(tester, english, karaoke: true);
    final first = r.wordRows.first.single;
    final last = r.wordRows.last.single;
    expect(last.top, greaterThan(first.top));
    // 不同行的填色范围不重叠。
    expect(first.bottom, lessThanOrEqualTo(last.top));
  });

  testWidgets('当前行逐字填色和普通状态排版一致', (tester) async {
    final idle = await _pump(tester, english);
    final idleSize = idle.size;
    final idleBoxes = idle.wordBoxes.map((b) => b.toList()).toList();
    final active = await _pump(tester, english, karaoke: true);
    expect(active.size, idleSize);
    expect(active.wordBoxes, idleBoxes);
  });

  testWidgets('有注音时行高加大，注音不改变字的位置顺序', (tester) async {
    final plain = await _pump(tester, [_w('偽', 0), _w('物', 100)], width: 400);
    final h = plain.size.height;
    final ruby = await _pump(tester, [_w('偽', 0, 'にせ'), _w('物', 100, 'もの')], width: 400);
    expect(ruby.size.height, greaterThan(h));
    expect(ruby.wordBoxes[0].single.left, lessThan(ruby.wordBoxes[1].single.left));
  });

  testWidgets('靠右对齐时撑满宽度，字贴右边', (tester) async {
    final r = await _pump(tester, [_w('右', 0)], width: 300, align: TextAlign.right);
    expect(r.size.width, 300);
    expect(r.wordBoxes.single.single.right, closeTo(300, 0.5));
  });
}
