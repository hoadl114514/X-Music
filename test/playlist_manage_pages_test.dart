import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/app/app.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/pages/library/playlist_editor.dart';
import 'package:netease_client/pages/library/playlist_page.dart';
import 'package:netease_client/pages/social/follow_page.dart';
import 'package:netease_client/state/account_controller.dart';
import 'package:netease_client/state/player_controller.dart';

import 'support/fakes.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const _own = {
  'id': 42,
  'name': '我的歌单',
  'description': '旧简介',
  'trackCount': 0,
  'creator': {'userId': 1, 'nickname': '我'},
};

/// 已登录（uid 1）的假接口，记下所有请求的路径。
MockClient _client(List<String> paths) => MockClient((r) async {
  final path = r.url.path;
  paths.add(path);
  if (path == '/api/nuser/account/get') {
    return _json({
      'code': 200,
      'profile': {'userId': 1, 'nickname': '我'},
    });
  }
  if (path == '/api/user/playlist') {
    final removed = paths.contains('/weapi/playlist/remove');
    final created = paths.contains('/weapi/playlist/create');
    return _json({
      'code': 200,
      'playlist': [
        if (!removed) _own,
        if (created)
          {
            'id': 43,
            'name': '新歌单',
            'creator': {'userId': 1, 'nickname': '我'},
          },
      ],
    });
  }
  if (path == '/weapi/playlist/create') {
    return _json({
      'code': 200,
      'id': 43,
      'playlist': {
        'id': 43,
        'name': '新歌单',
        'creator': {'userId': 1, 'nickname': '我'},
      },
    });
  }
  if (path == '/api/v6/playlist/detail') {
    return _json({
      'code': 200,
      'playlist': {
        ..._own,
        'trackIds': [
          for (final id in [1, 2, 3]) {'id': id},
        ],
      },
    });
  }
  if (path == '/api/v3/song/detail') {
    return _json({
      'code': 200,
      'songs': [
        for (final id in [1, 2, 3])
          {
            'id': id,
            'name': '歌$id',
            'dt': 200000,
            'ar': [
              {'id': 10, 'name': '歌手甲'},
              {'id': 11, 'name': '歌手乙'},
            ],
            'al': {'id': 20, 'name': '专辑$id'},
          },
      ],
    });
  }
  if (path == '/api/user/getfollows/1') {
    return _json({'code': 200, 'more': false, 'follow': []});
  }
  if (path == '/api/v1/event/get') {
    return _json({'code': 200, 'more': false, 'lasttime': 0, 'events': []});
  }
  return _json({'code': 200});
});

Future<void> _pump(WidgetTester tester, MockClient client, Widget page) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final f = await fakeServices(client: client);
  await f.services.account.loginWithCookies({'MUSIC_U': 'x'});
  await tester.pumpWidget(
    AppScope(
      services: f.services,
      child: AccountScope(
        controller: f.services.account,
        child: PlayerScope(
          controller: f.services.player,
          child: MaterialApp(home: page),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _playlist = Playlist(id: '42', name: '我的歌单', playCount: 0, creatorId: 1, creator: '我');

void main() {
  testWidgets('creating a playlist opens the new playlist', (tester) async {
    final paths = <String>[];
    await _pump(
      tester,
      _client(paths),
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCreatePlaylistDialog(context),
            child: const Text('新建'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新歌单');
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(paths, contains('/weapi/playlist/create'));
    expect(find.byType(PlaylistPage), findsOneWidget);
    expect(find.text('新歌单'), findsWidgets);
  });

  testWidgets('own playlist can be renamed from the manage menu', (tester) async {
    final paths = <String>[];
    await _pump(tester, _client(paths), const PlaylistPage(playlist: _playlist));
    await tester.tap(find.byTooltip('管理歌单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑歌单信息'));
    await tester.pumpAndSettle();
    expect(find.byType(PlaylistEditPage), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '名称'), '改过的名字');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(paths, contains('/eapi/playlist/update/name'));
    expect(find.byType(PlaylistEditPage), findsNothing);
  });

  testWidgets('deleting an own playlist asks first and closes the page', (tester) async {
    final paths = <String>[];
    await _pump(
      tester,
      _client(paths),
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PlaylistPage(playlist: _playlist)),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('管理歌单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除歌单'));
    await tester.pumpAndSettle();
    expect(find.textContaining('删除后无法恢复'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(paths, contains('/weapi/playlist/remove'));
    expect(find.byType(PlaylistPage), findsNothing);
  });

  testWidgets('posting from the follow tab sends the event', (tester) async {
    final paths = <String>[];
    await _pump(tester, _client(paths), const Scaffold(body: FollowPage()));
    await tester.tap(find.text('分享新鲜事…'));
    await tester.pumpAndSettle();
    expect(find.text('发动态'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '今天的歌很好听');
    await tester.pump();
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();
    expect(paths, contains('/api/share/friends/resource'));
    expect(find.text('发动态'), findsNothing);
    // 发完刷新列表：关注动态请求了两次。
    expect(paths.where((p) => p == '/api/v1/event/get'), hasLength(2));
  });

  testWidgets('song menu offers play next, like, collect, comments, share, artists, album', (
    tester,
  ) async {
    await _pump(tester, _client([]), const PlaylistPage(playlist: _playlist));
    expect(find.text('歌1'), findsOneWidget);
    await tester.tap(find.byTooltip('更多').first);
    await tester.pumpAndSettle();
    for (final t in ['下一首播放', '喜欢', '收藏到歌单', '从歌单中删除', '评论', '分享链接', '分享到动态']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('歌手：歌手甲 / 歌手乙'), findsOneWidget);
    expect(find.text('专辑：专辑1'), findsOneWidget);
  });

  testWidgets('batch delete removes the selected songs from an own playlist', (tester) async {
    final paths = <String>[];
    await _pump(tester, _client(paths), const PlaylistPage(playlist: _playlist));
    await tester.tap(find.text('批量删除'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 首'), findsOneWidget);
    await tester.tap(find.text('歌1'));
    await tester.tap(find.text('歌3'));
    await tester.pump();
    expect(find.text('已选 2 首'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 首歌'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(paths, contains('/eapi/playlist/manipulate/tracks'));
    expect(find.text('歌1'), findsNothing);
    expect(find.text('歌2'), findsOneWidget);
    expect(find.text('歌3'), findsNothing);
    expect(find.text('批量删除'), findsOneWidget);
  });
}
