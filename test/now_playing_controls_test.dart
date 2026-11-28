import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/app/app.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('播放控制只在封面页显示，百科页和歌词页收起', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final wiki = File('test/fixtures/song_wiki.json').readAsStringSync();
    final f = await fakeServices(
      client: MockClient((req) async {
        if (req.url.path.contains('song/play/about')) {
          return http.Response.bytes(utf8.encode(wiki), 200);
        }
        return http.Response('{"code":200}', 200);
      }),
    );
    await tester.pumpWidget(NeteaseClientApp(services: f.services));
    await f.services.player.playQueue([song('1'), song('2')], title: '测试');
    await f.services.player.pause();
    await tester.pump();
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    double factor() => tester.widget<AnimatedAlign>(find.byType(AnimatedAlign).last).heightFactor!;

    // 从歌词入口进来：在歌词页，控制收起。
    await tester.tap(find.byTooltip('歌词'));
    await settle();
    expect(factor(), 0);

    // 回到封面页：控制出现。
    final pages = find.byType(PageView);
    await tester.fling(pages, const Offset(400, 0), 1500);
    await settle();
    expect(factor(), 1);

    // 到百科页：控制收起。
    await tester.fling(pages, const Offset(400, 0), 1500);
    await settle();
    expect(find.text('音乐百科'), findsOneWidget);
    expect(factor(), 0);
  });
}
