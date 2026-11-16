import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/app/app.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/pages/library/track_list_view.dart';
import 'package:netease_client/shell/app_shell.dart';
import 'package:netease_client/shell/page_visit.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('track list refreshes in the background when its page is visited again', (
    tester,
  ) async {
    final f = await fakeServices();
    var loads = 0;
    var visit = 0;
    late StateSetter setOuter;
    Future<List<Song>> load() async {
      loads++;
      return [song('$loads')];
    }

    await tester.pumpWidget(NeteaseClientApp(services: f.services));
    await tester.pump();
    // 在应用里推一个页面，拿到 AppScope / PlayerScope。
    unawaited(
      Navigator.of(tester.element(find.byType(AppShell))).push(
        MaterialPageRoute<void>(
          builder: (_) => StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return Scaffold(
                body: PageVisit(
                  count: visit,
                  child: TrackListView(
                    load: load,
                    queueTitle: '测试',
                    header: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(loads, 1);
    expect(find.text('歌曲1'), findsOneWidget);

    // 重建但次数没变：不刷新。
    setOuter(() {});
    await tester.pump();
    expect(loads, 1);

    setOuter(() => visit++);
    await tester.pump();
    // 刷新时旧列表还在，拿到新数据后替换。
    expect(loads, 2);
    await tester.pump();
    expect(find.text('歌曲2'), findsOneWidget);
  });
}
