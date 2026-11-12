import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/app/app.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/pages/comments/comments_page.dart';
import 'package:netease_client/pages/now_playing/lyrics_copy.dart';
import 'package:netease_client/pages/now_playing/now_playing_page.dart';

import 'support/fakes.dart';

void main() {
  final queue = [song('1'), song('2')];

  Future<FakeBackend> pumpApp(WidgetTester tester, {bool withQueue = true}) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await fakeServices();
    f.backend.qualityMap['1'] = [AudioQuality.standard, AudioQuality.exhigh, AudioQuality.lossless];
    f.backend.lyricsMap[('1', LyricSource.netease)] = karaoke();
    await tester.pumpWidget(NeteaseClientApp(services: f.services));
    if (withQueue) {
      await f.services.player.playQueue(queue, title: '测试歌单');
      await f.services.player.pause();
    }
    await tester.pump();
    return f.backend;
  }

  // 播放页背景动画和进度计时器不会停，不能用 pumpAndSettle。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('home shows login prompts and recommendations when logged out', (tester) async {
    await pumpApp(tester, withQueue: false);
    expect(find.text('我的歌单'), findsOneWidget);
    expect(find.text('登录后查看你的歌单'), findsOneWidget);
    expect(find.text('私人 FM'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -600));
    await settle(tester);
    expect(find.text('推荐歌单'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    // 没有在放的歌时不显示迷你播放条。
    expect(find.byTooltip('歌词'), findsNothing);
  });

  testWidgets('avatar opens drawer; recent plays asks to log in', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('个人中心'));
    await settle(tester);
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('听歌排行'), findsOneWidget);

    await tester.tap(find.text('最近播放'));
    await settle(tester);
    expect(find.text('未登录'), findsNothing);
    expect(find.text('登录后查看最近播放'), findsOneWidget);
  });

  testWidgets('settings tab exposes quality, lyric source and login methods', (tester) async {
    await pumpApp(tester, withQueue: false);
    await tester.tap(find.byTooltip('个人中心'));
    await settle(tester);
    await tester.tap(find.text('设置'));
    await settle(tester);
    expect(find.text('默认音质'), findsOneWidget);
    expect(find.text('默认歌词来源'), findsOneWidget);
    await tester.tap(find.text('登录账号'));
    await settle(tester);
    // 默认是扫码；假接口没给 key，显示错误而不是一直转圈。
    expect(find.text('获取二维码失败'), findsOneWidget);
    expect(find.text('手机号'), findsNothing);
    await tester.tap(find.text('Cookie'));
    await settle(tester);
    expect(find.text('验证并登录'), findsOneWidget);
  });

  testWidgets('settings: audio cache limit can be picked or typed in', (tester) async {
    await pumpApp(tester, withQueue: false);
    await tester.tap(find.byTooltip('个人中心'));
    await settle(tester);
    await tester.tap(find.text('设置'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('听歌缓存上限'), 200);
    expect(find.text('5 GB'), findsOneWidget);
    expect(find.text('已用 0 B'), findsOneWidget);

    await tester.tap(find.text('听歌缓存上限'));
    await settle(tester);
    expect(find.text('5 GB（默认）'), findsOneWidget);
    await tester.tap(find.text('10 GB'));
    await settle(tester);
    expect(find.text('10 GB'), findsOneWidget);

    await tester.tap(find.text('听歌缓存上限'));
    await settle(tester);
    await tester.tap(find.text('自定义…'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '2.5');
    await tester.tap(find.text('确定'));
    await settle(tester);
    expect(find.text('2.5 GB'), findsOneWidget);
  });

  testWidgets('now playing: quality sheet lists only offered qualities', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('歌曲1').last);
    await settle(tester);
    expect(find.byType(NowPlayingPage), findsOneWidget);
    expect(find.text('测试歌单'), findsOneWidget);

    await tester.tap(find.text('极高')); // 默认 exhigh。
    await settle(tester);
    expect(find.text('无损'), findsOneWidget);
    expect(find.text('标准'), findsOneWidget);
    expect(find.text('Hi-Res'), findsNothing);
    expect(find.text('超清母带'), findsNothing);

    await tester.tap(find.text('无损'));
    await settle(tester);
    expect(find.text('无损'), findsOneWidget); // 进度条下方的音质标签。
  });

  testWidgets('lyrics page shows lyrics; menu switches source and offset', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('歌词'));
    await settle(tester);
    expect(find.byType(NowPlayingPage), findsOneWidget);
    expect(find.text('第0行翻译'), findsOneWidget);

    // 播放页里右滑回封面，再左滑回歌词；歌词按钮已经去掉。
    final pages = find.byType(PageView);
    await tester.fling(pages, const Offset(400, 0), 1500);
    await settle(tester);
    expect(find.text('第0行翻译'), findsNothing);
    expect(find.byTooltip('歌词'), findsNothing);
    await tester.fling(pages, const Offset(-400, 0), 1500);
    await settle(tester);
    expect(find.text('第0行翻译'), findsOneWidget);

    await tester.tap(find.byTooltip('更多'));
    await settle(tester);
    expect(find.text('歌词来源'), findsOneWidget);
    expect(find.textContaining('网易云 · 逐字 · 翻译'), findsOneWidget);
    await tester.tap(find.byTooltip('歌词提前 0.5s'));
    await tester.pump();
    expect(find.text('+0.5s'), findsOneWidget);

    // QQ 没有歌词：保留原歌词并提示。
    await tester.tap(find.text('QQ 音乐').last);
    await settle(tester);
    expect(find.text('QQ 音乐没有这首歌的歌词'), findsOneWidget);
  });

  testWidgets('long-press a lyric line to copy it or batch-select lines', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('歌词'));
    await settle(tester);
    await tester.longPress(find.text('第1行翻译'));
    await settle(tester);
    expect(find.text('复制这句'), findsOneWidget);
    await tester.tap(find.text('批量复制'));
    await settle(tester);
    expect(find.byType(LyricsCopyPage), findsOneWidget);
    expect(find.text('已选 1 句'), findsOneWidget);
    // 长按另一行：把两行之间全部选上。
    await tester.longPress(find.text('第4行翻译'));
    await tester.pump();
    expect(find.text('已选 4 句'), findsOneWidget);
    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(find.text('已选 8 句'), findsOneWidget);
    expect(
      lyricsText(karaoke().lines.take(2), translation: true),
      '字0字1字2字3\n第0行翻译\n字0字1字2字3\n第1行翻译',
    );
  });

  testWidgets('long-press song title offers copying title or artist', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('歌曲1').last);
    await settle(tester);
    await tester.longPress(find.text('歌手1').last);
    await settle(tester);
    expect(find.text('复制歌名'), findsOneWidget);
    expect(find.text('复制歌手'), findsOneWidget);
    expect(find.text('复制歌名 - 歌手'), findsOneWidget);
  });

  testWidgets('now playing opens the song comments', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('歌曲1').last);
    await settle(tester);
    await tester.tap(find.byTooltip('评论'));
    await settle(tester);
    expect(find.byType(CommentsPage), findsOneWidget);
    expect(find.text('热门'), findsOneWidget);
    expect(find.text('最新'), findsOneWidget);
    expect(find.text('还没有评论，来抢沙发吧 ~'), findsOneWidget);
    expect(find.text('说点什么吧'), findsOneWidget);
  });
}
