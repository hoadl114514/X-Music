import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/app/app.dart';
import 'package:netease_client/pages/social/social_widgets.dart';
import 'package:netease_client/state/account_controller.dart';
import 'package:netease_client/state/player_controller.dart';

import 'support/fakes.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _event(int id, int userId, String text, {int userType = 0}) => {
  'id': id,
  'type': 35,
  'eventTime': 1700000000000 + id,
  'user': {'userId': userId, 'nickname': '用户$userId', 'userType': userType},
  'json': jsonEncode({'msg': text}),
  'info': {'threadId': 'A_EV_2_${id}_$userId'},
};

/// 已登录（uid 1）的假接口。[sent] 记录发出去的私信。
MockClient _client({List<http.Request>? sent}) => MockClient((r) async {
  final path = r.url.path;
  if (path == '/api/nuser/account/get') {
    return _json({
      'code': 200,
      'profile': {'userId': 1, 'nickname': '我'},
    });
  }
  if (path == '/api/user/getfollows/1') {
    return _json({
      'code': 200,
      'more': false,
      'follow': [
        {'userId': 2, 'nickname': '好友甲', 'followed': true},
      ],
    });
  }
  if (path == '/api/v1/event/get') {
    return _json({
      'code': 200,
      'more': false,
      'lasttime': 0,
      'events': [_event(1, 2, '朋友的动态'), _event(2, 3, '音乐人的动态', userType: 4)],
    });
  }
  if (path == '/api/msg/private/users') {
    // 模拟服务端没及时清未读：不管看没看过，一直报 3 条未读。
    return _json({
      'code': 200,
      'more': false,
      'msgs': [
        {
          'fromUser': {'userId': 2, 'nickname': '好友甲'},
          'lastMsg': jsonEncode({'msg': '在吗'}),
          'lastMsgTime': 1700000000000,
          'newMsgCount': 3,
        },
      ],
    });
  }
  if (path == '/weapi/msg/private/history') {
    return _json({
      'code': 200,
      'more': false,
      'msgs': [
        {
          'id': 7,
          'time': 1700000000000,
          'fromUser': {'userId': 2, 'nickname': '好友甲'},
          'msg': jsonEncode({'msg': '在吗'}),
        },
      ],
    });
  }
  if (path == '/weapi/artist/sub') {
    sent?.add(r);
    return _json({'code': 200, 'message': 'success', 'data': null});
  }
  if (path.endsWith('/user/follow/2')) {
    return http.Response.bytes(utf8.encode(jsonEncode({'code': 250, 'message': '关注异常'})), 200);
  }
  if (path == '/eapi/msg/private/send') {
    sent?.add(r);
    return _json({'code': 200});
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
          child: MaterialApp(home: Scaffold(body: page)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a risk-controlled follow explains itself in a dialog', (tester) async {
    await _pump(tester, _client(), const Center(child: FollowButton(userId: 2, followed: false)));
    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法关注'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法关注'), findsNothing);
    expect(find.text('关注'), findsOneWidget);
  });

  testWidgets('an artist follow uses artist/sub instead of the user follow', (tester) async {
    final sent = <http.Request>[];
    await _pump(
      tester,
      _client(sent: sent),
      const Center(child: FollowButton(userId: 2, artistId: '12', followed: false)),
    );
    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();
    expect(sent.single.url.path, '/weapi/artist/sub');
    expect(find.text('暂时无法关注'), findsNothing);
    expect(find.text('已关注'), findsOneWidget);
  });
}
