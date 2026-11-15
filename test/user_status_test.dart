import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/api/eapi_crypto.dart';
import 'package:netease_client/api/netease_api.dart';
import 'package:netease_client/app/app.dart';
import 'package:netease_client/pages/user/user_page.dart';
import 'package:netease_client/shell/app_drawer.dart';
import 'package:netease_client/state/account_controller.dart';
import 'package:netease_client/state/player_controller.dart';

import 'support/fakes.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// 解出 EAPI 请求体里的接口路径和 JSON。
(String, Map<String, Object?>) _payload(http.Request r) {
  final hex = r.bodyFields['params']!;
  final bytes = Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
  final plain = EapiCrypto.decrypt(bytes).split('-36cd479b6b5-');
  return (plain.first, jsonDecode(plain[1]) as Map<String, Object?>);
}

const _options = {
  'code': 200,
  'data': [
    {'type': 'STUDY', 'iconUrl': 'http://p1.music.126.net/s.png', 'content': '学习中'},
    {'type': 'TEXT', 'content': '', 'canEdit': true, 'desc': '自定义状态'},
  ],
};

/// [status] 是 `/api/social/user/status` 返回的 data。
MockClient _client({
  int me = 1,
  Map<String, Object?> status = const {},
  List<http.Request>? seen,
}) => MockClient((r) async {
  seen?.add(r);
  final path = r.url.path;
  if (path == '/api/nuser/account/get') {
    return _json({
      'code': 200,
      'profile': {'userId': me, 'nickname': '我'},
    });
  }
  if (path.startsWith('/api/v1/user/detail/')) {
    return _json({
      'code': 200,
      'level': 3,
      'profile': {'userId': 100, 'nickname': '某人'},
    });
  }
  if (path == '/eapi/social/user/status') return _json({'code': 200, 'data': status});
  if (path == '/eapi/social/user/status/support') return _json(_options);
  if (path == '/eapi/social/user/status/edit') return _json({'code': 200, 'data': '将展示7天'});
  return _json({'code': 200});
});

Future<void> _pump(
  WidgetTester tester,
  MockClient client, {
  Widget home = const UserPage(userId: 100),
}) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final f = await fakeServices(client: client);
  await f.services.account.loginWithCookies({'MUSIC_U': 'u'});
  await tester.pumpWidget(
    AppScope(
      services: f.services,
      child: AccountScope(
        controller: f.services.account,
        child: PlayerScope(
          controller: f.services.player,
          child: MaterialApp(scaffoldMessengerKey: AppScope.messengerKey, home: home),
        ),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('api', () {
    NeteaseApi api(MockClient client) =>
        NeteaseApi(cookies: const {'MUSIC_U': 'u'}, client: client);

    test('userStatus reads the nested content and the attached song', () async {
      final seen = <http.Request>[];
      final s = await api(
        _client(
          seen: seen,
          status: {
            'userId': 100,
            'content': {
              'type': 'STUDY',
              'iconUrl': 'http://p1.music.126.net/s.png',
              'content': '学习中',
            },
            'song': {
              'id': 5,
              'name': '歌',
              'ar': [
                {'id': 2, 'name': '歌手'},
              ],
              'al': {'id': 3, 'name': '专辑'},
              'dt': 1000,
            },
          },
        ),
      ).userStatus(100);
      expect(s!.type, 'STUDY');
      expect(s.content, '学习中');
      expect(s.iconUrl, 'https://p1.music.126.net/s.png');
      expect(s.song?.title, '歌');
      final (path, body) = _payload(seen.single);
      expect(path, '/api/social/user/status');
      expect(body['visitorId'], '100');
    });

    test('userStatus also reads a flat or JSON-string status and returns null when empty', () {
      expect(
        NeteaseApi.parseUserStatus({
          'content': jsonEncode({'type': 'TEXT', 'content': '摸鱼'}),
        })?.content,
        '摸鱼',
      );
      expect(NeteaseApi.parseUserStatus({'type': 'TEXT', 'content': '发呆'})?.content, '发呆');
      expect(NeteaseApi.parseUserStatus(const <String, Object?>{}), isNull);
      expect(NeteaseApi.parseUserStatus(null), isNull);
    });

    test('statusOptions and setStatus', () async {
      final seen = <http.Request>[];
      final a = api(_client(seen: seen));
      final options = await a.statusOptions();
      expect([for (final o in options) o.content], ['学习中', '']);
      expect(options[1].canEdit, isTrue);
      expect(options[1].desc, '自定义状态');

      final hint = await a.setStatus(options[1].copyWith(content: '写代码'));
      expect(hint, '将展示7天');
      final (path, body) = _payload(seen.last);
      expect(path, '/api/social/user/status/edit');
      final content = jsonDecode(body['content']! as String) as Map;
      expect(content['type'], 'TEXT');
      expect(content['content'], '写代码');
    });

    test('sameStatusUsers parses the users and their tags', () async {
      final r = await api(
        MockClient(
          (_) async => _json({
            'code': 200,
            'data': {
              'rcmdTitle': '和你一样在学习的人',
              'statusContentDTO': {'type': 'STUDY', 'content': '学习中'},
              'userRcmdInfoVOList': [
                {
                  'userId': 7,
                  'nickName': '同学',
                  'avatarUrl': 'http://p1.music.126.net/a.jpg',
                  'statusContentDTO': {'type': 'STUDY', 'content': '学习中'},
                  'tagRcmdVOList': [
                    {'name': '都喜欢周杰伦', 'match': true},
                  ],
                },
              ],
            },
          }),
        ),
      ).sameStatusUsers();
      expect(r.title, '和你一样在学习的人');
      expect(r.status?.content, '学习中');
      expect(r.users.single.nickname, '同学');
      expect(r.users.single.tags, ['都喜欢周杰伦']);
    });
  });

  testWidgets('another user status shows under the profile', (tester) async {
    await _pump(
      tester,
      _client(
        status: {
          'content': {'type': 'STUDY', 'content': '学习中'},
        },
      ),
    );
    expect(find.text('学习中'), findsOneWidget);
    expect(find.text('添加状态'), findsNothing);
  });

  testWidgets('another user without a status shows nothing', (tester) async {
    await _pump(tester, _client());
    expect(find.text('添加状态'), findsNothing);
  });

  testWidgets('on my own page I can pick a status', (tester) async {
    final seen = <http.Request>[];
    await _pump(tester, _client(me: 100, seen: seen));
    await tester.tap(find.text('添加状态'));
    await tester.pumpAndSettle();
    expect(find.text('设置状态'), findsOneWidget);
    expect(find.text('自定义'), findsOneWidget);

    await tester.tap(find.text('学习中'));
    await tester.pumpAndSettle();
    expect(find.text('设置状态'), findsNothing);
    expect(find.text('学习中'), findsOneWidget);
    expect(find.text('添加状态'), findsNothing);
    expect(find.text('状态已设置，将展示7天'), findsOneWidget);
    expect(seen.where((r) => r.url.path == '/eapi/social/user/status/edit'), hasLength(1));
  });

  testWidgets('a custom status asks for the text', (tester) async {
    await _pump(tester, _client(me: 100));
    await tester.tap(find.text('添加状态'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '写代码');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('写代码'), findsOneWidget);
  });

  testWidgets('the drawer no longer has a status entry', (tester) async {
    await _pump(
      tester,
      _client(
        status: {
          'content': {'type': 'STUDY', 'content': '学习中'},
        },
      ),
      home: Scaffold(body: AppDrawer(onSelect: (_) {})),
    );
    expect(find.text('听歌状态'), findsNothing);
    expect(find.text('学习中'), findsNothing);
    expect(find.text('添加好友'), findsOneWidget);
  });
}
