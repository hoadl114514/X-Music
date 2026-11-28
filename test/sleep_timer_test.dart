import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/app/app.dart';
import 'package:netease_client/pages/now_playing/song_menu.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('定时关闭可以自定义时长', (tester) async {
    final f = await fakeServices();
    await tester.pumpWidget(NeteaseClientApp(services: f.services));
    await f.services.player.playQueue([song('1')], title: 't');
    await f.services.player.pause();
    await tester.pump();
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final context = tester.element(find.byType(Navigator).first);
    unawaited(showSleepTimerSheet(context));
    await settle();
    await tester.tap(find.text('自定义…'));
    await settle();
    expect(find.byType(CupertinoTimerPicker), findsOneWidget);
    await tester.tap(find.text('确定'));
    await settle();

    final left = f.services.player.sleepAt!.difference(DateTime.now());
    expect(left.inMinutes, inInclusiveRange(29, 30));
    f.services.player.setSleepTimer(null);
  });
}
