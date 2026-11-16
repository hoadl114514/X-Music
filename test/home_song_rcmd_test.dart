import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/app/app.dart';
import 'package:netease_client/pages/home_page.dart';

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
        'blockCode': 'HOMEPAGE_BLOCK_MGC_PLAYLIST',
        'uiElement': {
          'subTitle': {'title': '某人的雷达歌单'},
        },
        'creatives': [
          for (var i = 1; i <= 3; i++)
            {
              'resources': [
                {
                  'resourceType': 'list',
                  'resourceId': '${900 + i}',
                  'uiElement': {
                    'mainTitle': {'title': '雷达$i'},
                    'image': {'imageUrl': 'http://p1.music.126.net/r/$i.jpg'},
                  },
                  'resourceExtInfo': {'playCount': 25480000000},
                },
              ],
            },
        ],
      },
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
  setUp(resetHomeCaches);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

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

    // 雷达歌单在歌曲推荐下面。
    expect(find.text('某人的雷达歌单'), findsOneWidget);
    expect(find.text('雷达1'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('某人的雷达歌单')).dy,
      greaterThan(tester.getTopLeft(find.text('根据你喜爱的歌曲推荐')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide home shows several columns with page buttons', (tester) async {
    await pumpHome(tester, const Size(1000, 1400));
    expect(find.text('推荐1'), findsOneWidget);
    expect(find.text('推荐4').hitTestable(), findsOneWidget);
    expect(find.byTooltip('下一页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drawer opens the new songs page and goes back home', (tester) async {
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

    // 抽屉最上面的「首页」回到首页。
    await tester.tap(find.byTooltip('个人中心'));
    await settle(tester);
    await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('首页')));
    await settle(tester);
    expect(find.text('华语'), findsNothing);
    expect(find.text('根据你喜爱的歌曲推荐'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home keeps its data after switching tabs; refresh fetches again', (tester) async {
    await pumpHome(tester, const Size(400, 1400));
    int fetches() => requests.where((p) => p == '/api/homepage/block/page').length;
    expect(fetches(), 1);

    await tester.tap(find.text('发现'));
    await settle(tester);
    await tester.tap(find.text('首页'));
    await settle(tester);
    expect(find.text('推荐1'), findsOneWidget);
    expect(fetches(), 1);
    // 首页切走后不销毁，推荐歌单也不重新拉。
    expect(requests.where((p) => p == '/api/personalized/playlist').length, 1);

    await tester.tap(find.byTooltip('换一批'));
    await settle(tester);
    expect(fetches(), 2);
    expect(tester.takeException(), isNull);
  });
}
