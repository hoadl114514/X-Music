import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/app/app.dart';

import 'support/fakes.dart';

/// 官方首页里一首推荐歌曲（resourceExtInfo.song 是新版格式）。
Map<String, Object?> _resource(int i, {List<String>? labels, Map<String, Object?>? sub}) => {
  'resourceType': 'song',
  'resourceId': '$i',
  'uiElement': {
    'mainTitle': {'title': '推荐$i'},
    'labelTexts': ?labels,
    'subTitle': ?sub,
  },
  'resourceExtInfo': {
    'song': {
      'id': i,
      'name': '推荐$i',
      'ar': [
        {'id': 100 + i, 'name': '歌手$i'},
      ],
      'al': {'id': 200 + i, 'name': '专辑$i', 'picUrl': 'http://p1.music.126.net/x/$i.jpg'},
      'dt': 180000,
    },
    'songPrivilege': {'playMaxBrLevel': i == 3 ? 'lossless' : 'exhigh'},
  },
};

Map<String, Object?> _homepage() => {
  'code': 200,
  'data': {
    'blocks': [
      {'blockCode': 'HOMEPAGE_BANNER'},
      {
        'blockCode': 'HOMEPAGE_BLOCK_STYLE_RCMD',
        'uiElement': {
          'subTitle': {'title': '根据你喜爱的歌曲推荐'},
        },
        'creatives': [
          for (var c = 0; c < 3; c++)
            {
              'resources': [
                for (var i = c * 3 + 1; i <= c * 3 + 3; i++)
                  _resource(
                    i,
                    labels: i == 1 ? ['单曲循环的日语歌'] : null,
                    sub: i == 2
                        ? {'title': '昨日上万播放', 'titleType': 'songRcmdTag'}
                        : i == 4
                        ? {'title': '一条很长的热评摘录', 'titleType': 'songRcmdFromComment'}
                        : null,
                  ),
              ],
            },
        ],
      },
    ],
  },
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
      if (req.url.path == '/api/homepage/block/page') {
        return http.Response(
          jsonEncode(_homepage()),
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

  testWidgets('home shows song recommendations in columns of three (phone)', (tester) async {
    await pumpHome(tester, const Size(400, 1400));
    expect(requests, contains('/api/homepage/block/page'));
    expect(find.text('根据你喜爱的歌曲推荐'), findsOneWidget);
    expect(find.text('推荐1'), findsOneWidget);
    expect(find.text('歌手1'), findsOneWidget);
    expect(find.text('单曲循环的日语歌'), findsOneWidget);
    expect(find.text('昨日上万播放'), findsOneWidget);
    // 没有推荐理由时显示音质角标；热评摘录不当标签。
    expect(find.text('SQ'), findsOneWidget);
    expect(find.text('一条很长的热评摘录'), findsNothing);
    // 第 4 首在第二列，只露出一角。
    expect(find.text('推荐4').hitTestable(), findsNothing);
    expect(find.byTooltip('下一页'), findsNothing);

    await tester.drag(find.text('推荐2'), const Offset(-300, 0));
    // 翻页动画期间列表不接收点击，等它停稳。
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('推荐4').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide home shows several columns with page buttons', (tester) async {
    await pumpHome(tester, const Size(1000, 1400));
    expect(find.text('推荐1'), findsOneWidget);
    expect(find.text('推荐4').hitTestable(), findsOneWidget);
    expect(find.byTooltip('下一页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drawer opens the new songs page', (tester) async {
    await pumpHome(tester, const Size(400, 900));
    await tester.tap(find.byTooltip('个人中心'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('新歌速递'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(requests, contains('/api/v1/discovery/new/songs'));
    expect(find.text('华语'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
