import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/app/app.dart';

import 'support/fakes.dart';

/// 旧版接口格式的新歌（artists / album / alias）。
Map<String, Object?> _newSong(int i) => {
  'id': i,
  'name': '新歌$i',
  'alias': i == 1 ? ['别名'] : [],
  'artists': [
    {'id': 100 + i, 'name': '歌手$i'},
  ],
  'album': {'id': 200 + i, 'name': '专辑$i', 'picUrl': 'http://p1.music.126.net/x/$i.jpg'},
  'duration': 180000,
};

void main() {
  final requests = <String>[];

  Future<void> pumpHome(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    requests.clear();
    final client = MockClient((req) async {
      requests.add(req.url.path);
      if (req.url.path == '/api/personalized/newsong') {
        return http.Response(
          jsonEncode({
            'code': 200,
            'result': [
              for (var i = 1; i <= 10; i++) {'id': i, 'song': _newSong(i)},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('{"code":200}', 200);
    });
    final f = await fakeServices(client: client);
    await tester.pumpWidget(NeteaseClientApp(services: f.services));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('home shows new songs in columns of four (phone)', (tester) async {
    await pumpHome(tester, const Size(400, 1400));
    expect(requests, contains('/api/personalized/newsong'));
    expect(find.text('新歌精选'), findsOneWidget);
    expect(find.text('新歌1'), findsOneWidget);
    expect(find.text('歌手1'), findsOneWidget);
    expect(find.text('新歌4'), findsOneWidget);
    // 第 5 首在第二列，第二列只露出一角，歌名在屏幕外。
    expect(find.text('新歌5').hitTestable(), findsNothing);
    // 手机上没有翻页按钮。
    expect(find.byTooltip('下一页'), findsNothing);

    await tester.drag(find.text('新歌2'), const Offset(-300, 0));
    // 翻页动画期间列表不接收点击，等它停稳。
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('新歌5').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide home shows several columns with page buttons', (tester) async {
    await pumpHome(tester, const Size(1000, 1400));
    expect(find.text('新歌1'), findsOneWidget);
    expect(find.text('新歌5').hitTestable(), findsOneWidget);
    expect(find.byTooltip('下一页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
