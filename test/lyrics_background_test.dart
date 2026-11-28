import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/app/app.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/lyrics/ttml_parser.dart';
import 'package:netease_client/pages/now_playing/karaoke_text.dart';

import 'support/fakes.dart';

// 第 1 行 2 秒开始，背景人声 3 秒才开始；第 2 行 6 秒开始。
const _ttml =
    '<tt><body><div>'
    '<p begin="2" end="5"><span begin="2" end="5">main</span>'
    '<span ttm:role="x-bg" begin="3" end="5"><span begin="3" end="5">(harmony)</span></span></p>'
    '<p begin="6" end="8"><span begin="6" end="8">next</span></p>'
    '</div></body></tt>';

void main() {
  Finder harmony() => find.byWidgetPredicate(
    (w) => w is KaraokeText && w.words.map((x) => x.text).join() == 'harmony',
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('背景人声没唱到时隐藏，唱到时出现，唱过保持显示', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await fakeServices();
    f.backend.lyricsMap[('1', LyricSource.netease)] = TtmlParser.parse(
      _ttml,
      source: LyricSource.amll,
    );
    await tester.pumpWidget(NeteaseClientApp(services: f.services));
    await f.services.player.playQueue([song('1')], title: 't');
    await f.services.player.pause();
    await tester.pump();
    await tester.tap(find.byTooltip('歌词'));
    await settle(tester);

    expect(harmony(), findsNothing, reason: '还没到这一行');
    await f.services.player.seek(const Duration(milliseconds: 2500));
    await settle(tester);
    expect(harmony(), findsNothing, reason: '这一行开始了，但背景人声还没开始');
    await f.services.player.seek(const Duration(milliseconds: 3500));
    await settle(tester);
    expect(harmony(), findsOneWidget);
    await f.services.player.seek(const Duration(milliseconds: 6500));
    await settle(tester);
    expect(harmony(), findsOneWidget, reason: '唱过的行保持显示');
  });
}
