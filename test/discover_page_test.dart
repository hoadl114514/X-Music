import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/app/app.dart';
import 'package:netease_client/pages/library/followed_artists_page.dart';
import 'package:netease_client/pages/music/nav.dart';

import 'support/fakes.dart';

void main() {
  final forms = <String, List<String>>{};

  Map<String, Object?> playlist(String id, String name) => {
    'id': id,
    'name': name,
    'coverImgUrl': null,
    'playCount': 10,
    'trackCount': 3,
  };

  MockClient client() => MockClient((req) async {
    forms.putIfAbsent(req.url.path, () => []).add(req.body);
    final body = switch (req.url.path) {
      '/weapi/playlist/list' => {
        'code': 200,
        'more': false,
        'playlists': [playlist('1', '广场歌单A'), playlist('2', '广场歌单B')],
      },
      '/weapi/playlist/highquality/list' => {
        'code': 200,
        'more': false,
        'lasttime': 123,
        'playlists': [playlist('3', '精品歌单C')],
      },
      '/weapi/playlist/catalogue' => {
        'code': 200,
        'categories': {'0': '语种', '1': '风格'},
        'sub': [
          {'name': '华语', 'category': 0},
          {'name': '流行', 'category': 1},
        ],
      },
      '/api/nuser/account/get' => {
        'code': 200,
        'profile': {'userId': 7, 'nickname': '我'},
      },
      '/weapi/artist/sublist' => {
        'code': 200,
        'hasMore': false,
        'data': [
          {'id': 11, 'name': '关注的歌手', 'albumSize': 4},
        ],
      },
      _ => {'code': 200},
    };
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('playlist square switches type and category', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    forms.clear();
    final f = await fakeServices(client: client());
    await tester.pumpWidget(NeteaseClientApp(services: f.services));
    await settle(tester);
    await tester.tap(find.text('发现'));
    await settle(tester);
    expect(find.text('广场歌单A'), findsOneWidget);
    expect(find.text('全部歌单'), findsOneWidget);

    await tester.tap(find.text('精品'));
    await settle(tester);
    expect(find.text('精品歌单C'), findsOneWidget);
    expect(find.text('广场歌单A'), findsNothing);

    await tester.tap(find.text('全部歌单'));
    await settle(tester);
    expect(find.text('语种'), findsOneWidget);
    await tester.tap(find.text('流行'));
    await settle(tester);
    // 选了分类后按钮显示分类名，并按新分类重新加载。
    expect(find.text('流行'), findsOneWidget);
    expect(forms['/weapi/playlist/highquality/list']!.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('followed artists list loads for a logged-in account', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await fakeServices(client: client());
    await tester.runAsync(() => f.services.account.loginWithCookies({'MUSIC_U': 'x'}));
    await tester.pumpWidget(NeteaseClientApp(services: f.services));
    await settle(tester);
    final ctx = tester.element(find.byType(Scaffold).first);
    unawaited(SubPage.push(ctx, const SubPage(title: '艺人', body: FollowedArtistsPage())));
    await settle(tester);
    expect(find.text('关注的歌手'), findsOneWidget);
    expect(find.text('专辑 4'), findsOneWidget);
  });
}
