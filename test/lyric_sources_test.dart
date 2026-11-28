import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/app/app.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/pages/lyric_sources_page.dart';
import 'package:netease_client/state/player_controller.dart';

import 'support/fakes.dart';

void main() {
  group('AppSettings 歌词来源', () {
    test('默认顺序：网易云 → AMLL → QQ', () async {
      final s = await testSettings();
      expect(s.lyricSourceOrder, [LyricSource.netease, LyricSource.amll, LyricSource.qq]);
      expect(s.lyricSources, s.lyricSourceOrder);
      expect(s.lyricSource, LyricSource.netease);
    });

    test('旧版「默认歌词来源」放到最前', () async {
      final s = await testSettings({'lyric_source': 'qq'});
      expect(s.lyricSourceOrder, [LyricSource.qq, LyricSource.netease, LyricSource.amll]);
    });

    test('保存的顺序缺来源时补到最后，未知名字忽略', () async {
      final s = await testSettings({
        'lyric_source_order': ['amll', 'nope', 'qq'],
      });
      expect(s.lyricSourceOrder, [LyricSource.amll, LyricSource.qq, LyricSource.netease]);
    });

    test('关闭的来源不参与自动获取，至少保留一个', () async {
      final s = await testSettings();
      s.setLyricSourceEnabled(LyricSource.netease, false);
      s.setLyricSourceEnabled(LyricSource.qq, false);
      expect(s.lyricSources, [LyricSource.amll]);
      s.setLyricSourceEnabled(LyricSource.amll, false);
      expect(s.lyricSources, [LyricSource.amll], reason: '最后一个不能关');
      s.setLyricSourceEnabled(LyricSource.qq, true);
      expect(s.lyricSources, [LyricSource.amll, LyricSource.qq]);
    });
  });

  testWidgets('播放时按设置的顺序取歌词', (tester) async {
    final f = await fakeServices();
    f.services.settings.lyricSourceOrder = [LyricSource.amll, LyricSource.qq, LyricSource.netease];
    f.services.settings.setLyricSourceEnabled(LyricSource.qq, false);
    await f.services.player.playQueue([song('1')], title: 't');
    await tester.pump();
    final (source, fallback, order) = f.backend.lyricRequests.last;
    expect(source, LyricSource.amll);
    expect(fallback, isTrue);
    expect(order, [LyricSource.amll, LyricSource.netease]);
    await f.services.player.pause();
  });

  testWidgets('改了顺序立即按新顺序重新取当前这首的歌词', (tester) async {
    final f = await fakeServices();
    f.backend.lyricsMap[('1', LyricSource.netease)] = karaoke();
    f.backend.lyricsMap[('1', LyricSource.qq)] = karaoke(source: LyricSource.qq);
    await f.services.player.playQueue([song('1')], title: 't');
    await f.services.player.pause();
    await tester.pump();
    expect(f.services.player.lyrics.source, LyricSource.netease);

    // AMLL 放第一但没有这首，接着是 QQ。
    f.services.settings.lyricSourceOrder = [LyricSource.amll, LyricSource.qq, LyricSource.netease];
    await f.services.player.reloadLyrics();
    expect(f.backend.lyricRequests.last.$1, LyricSource.amll);
    expect(f.services.player.lyrics.source, LyricSource.qq);
  });

  testWidgets('慢的旧请求晚回来时不覆盖新请求的结果', (tester) async {
    final f = await fakeServices();
    f.backend.lyricsMap[('1', LyricSource.netease)] = karaoke();
    f.backend.lyricsMap[('1', LyricSource.qq)] = karaoke(source: LyricSource.qq);
    final slow = Completer<void>();
    f.backend.lyricsGate = (s) => s == LyricSource.netease ? slow.future : Future.value();
    await f.services.player.playQueue([song('1')], title: 't');
    await f.services.player.pause();
    await tester.pump();

    f.services.settings.lyricSourceOrder = [LyricSource.qq, LyricSource.netease, LyricSource.amll];
    await f.services.player.reloadLyrics();
    expect(f.services.player.lyrics.source, LyricSource.qq);

    slow.complete();
    await tester.pump();
    expect(f.services.player.lyrics.source, LyricSource.qq);
  });

  testWidgets('歌词来源页：开关和拖动排序', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await fakeServices();
    await tester.pumpWidget(
      AppScope(
        services: f.services,
        child: PlayerScope(
          controller: f.services.player,
          child: const MaterialApp(home: LyricSourcesPage()),
        ),
      ),
    );
    expect(find.text('AMLL'), findsOneWidget);

    // 关掉 QQ。
    await tester.tap(find.byType(Switch).at(2));
    await tester.pump();
    expect(f.services.settings.lyricSources, [LyricSource.netease, LyricSource.amll]);

    // 把 AMLL 拖到最前。
    final handle = find.byIcon(Icons.drag_handle_rounded).at(1);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(f.services.settings.lyricSourceOrder.first, LyricSource.amll);
  });
}
