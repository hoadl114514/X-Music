import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/app/app.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/pages/now_playing/lyrics_view.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('间奏时浮出三个点，下一句开始后收起', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await fakeServices();
    // 第 1 行 1–3 秒，第 2 行 12 秒开始：中间空 9 秒。
    LyricLine line(int s, int e, String t) => LyricLine(
      start: Duration(seconds: s),
      end: Duration(seconds: e),
      words: [LyricWord(t, Duration(seconds: s), Duration(seconds: e))],
    );
    f.backend.lyricsMap[('1', LyricSource.netease)] = Lyrics(
      lines: [line(1, 3, 'one'), line(12, 14, 'two')],
      source: LyricSource.amll,
      wordSynced: true,
    );
    await tester.pumpWidget(NeteaseClientApp(services: f.services));
    await f.services.player.playQueue([song('1')], title: 't');
    await f.services.player.pause();
    await tester.pump();
    await tester.tap(find.byTooltip('歌词'));
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    bool shown() {
      final dots = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is InterludeDotsPainter,
      );
      // 一共两段：前奏（0–1 秒，太短不算）不算；只有 3–12 秒这一段。
      expect(dots, findsOneWidget);
      final fade = tester.widget<AnimatedCrossFade>(
        find.ancestor(of: dots, matching: find.byType(AnimatedCrossFade)).first,
      );
      return fade.crossFadeState == CrossFadeState.showSecond;
    }

    await f.services.player.seek(const Duration(seconds: 2));
    await settle();
    expect(shown(), isFalse, reason: '还在唱第一句');
    await f.services.player.seek(const Duration(seconds: 6));
    await settle();
    expect(shown(), isTrue);
    await f.services.player.seek(const Duration(seconds: 12, milliseconds: 500));
    await settle();
    expect(shown(), isFalse, reason: '下一句开始了');
  });
}
