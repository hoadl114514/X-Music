import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/app/app.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('swipe left plays next, swipe right plays previous, neighbour shows while dragging', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await fakeServices();
    await tester.pumpWidget(NeteaseClientApp(services: f.services));
    final player = f.services.player;
    await player.playQueue([song('1'), song('2'), song('3')], title: '测试');
    await tester.pump();

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    // 拖到一半：下一首的信息从右边露出来。
    final gesture = await tester.startGesture(tester.getCenter(find.text('歌曲1')));
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    expect(find.text('歌曲2'), findsOneWidget);
    await gesture.moveBy(const Offset(-80, 0));
    await gesture.up();
    await settle();
    expect(player.song.id, '2');

    await tester.drag(find.text('歌曲2'), const Offset(200, 0));
    await settle();
    expect(player.song.id, '1');

    // 滑得不够远：回弹，不切歌。
    await tester.drag(find.text('歌曲1'), const Offset(-30, 0));
    await settle();
    expect(player.song.id, '1');
    await player.pause();
  });
}
