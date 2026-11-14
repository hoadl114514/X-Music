import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/app/app.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/pages/now_playing/lyrics_view.dart';
import 'package:netease_client/pages/now_playing/now_playing_page.dart';
import 'package:netease_client/shell/desktop_player_bar.dart';
import 'package:netease_client/shell/desktop_shell.dart';

import 'support/fakes.dart';

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<FakeBackend> pumpDesktop(WidgetTester tester, Size size) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await fakeServices();
    f.backend.lyricsMap[('1', LyricSource.netease)] = karaoke();
    await tester.pumpWidget(NeteaseClientApp(services: f.services));
    await f.services.player.playQueue([song('1'), song('2')], title: '测试歌单');
    await f.services.player.pause();
    await settle(tester);
    return f.backend;
  }

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('wide window uses sidebar, content and bottom player bar', (tester) async {
    await pumpDesktop(tester, const Size(1280, 800));
    expect(find.byType(DesktopShell), findsOneWidget);
    expect(find.byType(DesktopPlayerBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    // 手机端的悬浮播放条（带「歌词」按钮的那条）不显示，只有电脑播放条上的一个。
    expect(find.byTooltip('歌词'), findsOneWidget);
    expect(find.text('歌曲1'), findsWidgets);

    await tester.tap(find.text('我喜欢的音乐').first);
    await settle(tester);
    expect(find.text('登录后查看你喜欢的音乐'), findsOneWidget);
    // 导航栏和播放条留在原位。
    expect(find.byType(DesktopPlayerBar), findsOneWidget);

    await tester.tap(find.byTooltip('播放'));
    await settle(tester);
    expect(find.byTooltip('暂停'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('narrow window falls back to the phone layout', (tester) async {
    await pumpDesktop(tester, const Size(600, 900));
    expect(find.byType(DesktopShell), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('wide now playing shows cover and lyrics side by side', (tester) async {
    await pumpDesktop(tester, const Size(1280, 800));
    await tester.tap(find.byTooltip('歌词'));
    await settle(tester);
    expect(find.byType(NowPlayingPage), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(LyricsView), findsOneWidget);
    expect(find.text('歌曲1'), findsWidgets);
    debugDefaultTargetPlatformOverride = null;
  });
}
