import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/app/app.dart';
import 'package:netease_client/pages/library/library_page.dart';
import 'package:netease_client/state/account_controller.dart';
import 'package:netease_client/state/player_controller.dart';

import 'support/fakes.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  late List<String> paths;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    paths = [];
    final client = MockClient((r) async {
      final path = r.url.path;
      paths.add(path);
      if (path == '/api/nuser/account/get') {
        return _json({
          'code': 200,
          'profile': {'userId': 1, 'nickname': '我'},
        });
      }
      if (path == '/api/user/playlist') {
        final unsubscribed = paths.any((p) => p.endsWith('/playlist/unsubscribe'));
        return _json({
          'code': 200,
          'playlist': [
            {
              'id': 1,
              'name': '我喜欢的音乐',
              'specialType': 5,
              'trackCount': 321,
              'creator': {'userId': 1, 'nickname': '我'},
            },
            {
              'id': 42,
              'name': '自建歌单',
              'trackCount': 7,
              'creator': {'userId': 1, 'nickname': '我'},
            },
            {
              'id': 43,
              'name': '一起建的歌',
              'trackCount': 12,
              // 真实返回：共享歌单 specialType 300，列表里的成员只有 userId。
              'specialType': 300,
              'creator': {'userId': 1, 'nickname': '我'},
              'sharedUsers': [
                {'userId': 5},
              ],
            },
            if (!unsubscribed)
              {
                'id': 99,
                'name': '别人的歌单',
                'trackCount': 50,
                'subscribed': true,
                'creator': {'userId': 2, 'nickname': '别人'},
              },
          ],
        });
      }
      if (path == '/api/v6/playlist/detail' && r.bodyFields['id'] == '43') {
        // 歌单详情里的成员带昵称和头像。
        return _json({
          'code': 200,
          'playlist': {
            'id': 43,
            'name': '一起建的歌',
            'specialType': 300,
            'trackIds': <Object>[],
            'creator': {'userId': 1, 'nickname': '我'},
            'sharedUsers': [
              {'userId': 5, 'nickname': '好友'},
            ],
          },
          'sharedPrivilege': {'status': 'SHARED', 'usePermission': 'NORMAL'},
        });
      }
      return _json({'code': 200});
    });
    final f = await fakeServices(client: client);
    await f.services.account.loginWithCookies({'MUSIC_U': 'x'});
    await tester.pumpWidget(
      AppScope(
        services: f.services,
        child: AccountScope(
          controller: f.services.account,
          child: PlayerScope(
            controller: f.services.player,
            child: const MaterialApp(home: Scaffold(body: LibraryPage())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('library lists liked, created and collected playlists', (tester) async {
    await pump(tester);
    // 登录时拉一次，进入音乐库后台再刷新一次。
    expect(paths.where((p) => p == '/api/user/playlist').length, 2);
    expect(find.text('我喜欢的音乐'), findsOneWidget);
    expect(find.text('321 首'), findsOneWidget);
    // 最近播放、听歌排行从原来的侧栏搬到了音乐库。
    expect(find.text('最近播放'), findsOneWidget);
    expect(find.text('听歌排行'), findsOneWidget);
    expect(find.text('艺人'), findsOneWidget);
    // 「新建」可以选普通歌单或共建歌单。
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    expect(find.text('共建歌单'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('创建的歌单'), findsOneWidget);
    expect(find.text('7 首'), findsOneWidget);
    expect(find.text('自建歌单'), findsOneWidget);
    expect(find.text('收藏的歌单'), findsOneWidget);
    expect(find.text('别人的歌单'), findsOneWidget);
    // 「我喜欢」只在顶部卡片里，不重复出现在创建的歌单里。
    expect(find.text('3'), findsNothing);

    // 自建歌单的管理菜单。
    await tester.tap(find.byTooltip('管理歌单').first);
    await tester.pumpAndSettle();
    expect(find.text('编辑歌单信息'), findsOneWidget);
    expect(find.text('删除歌单'), findsOneWidget);
  });

  testWidgets('collected playlist can be unsubscribed from the library', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('管理歌单').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消收藏'));
    await tester.pumpAndSettle();
    // 确认对话框。
    await tester.tap(find.widgetWithText(FilledButton, '取消收藏'));
    await tester.pumpAndSettle();
    expect(paths.any((p) => p.endsWith('/playlist/unsubscribe')), isTrue);
    expect(find.text('别人的歌单'), findsNothing);
    expect(find.text('还没有收藏歌单'), findsOneWidget);
  });

  testWidgets('a shared playlist shows invite friends under its name; a normal one does not', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('一起建的歌'));
    await tester.pumpAndSettle();
    expect(find.text('邀请好友'), findsOneWidget);
    // 成员昵称从歌单详情补全，头像位置显示昵称首字。
    expect(find.text('好'), findsOneWidget);
    expect(find.text('?'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('自建歌单'));
    await tester.pumpAndSettle();
    expect(find.text('邀请好友'), findsNothing);
  });
}
