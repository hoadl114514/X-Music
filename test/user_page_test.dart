import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/app/app.dart';
import 'package:netease_client/data/models.dart';
import 'package:netease_client/pages/user/user_page.dart';
import 'package:netease_client/state/account_controller.dart';
import 'package:netease_client/state/player_controller.dart';

import 'support/fakes.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object> _song(int id) => {
  'id': id,
  'name': '热歌$id',
  'ar': [
    {'id': 12, 'name': '某歌手'},
  ],
  'al': {'id': 9, 'name': '专辑'},
  'dt': 1000,
};

Map<String, Object> _playlist(int id, int creator, {int special = 0}) => {
  'id': id,
  'name': special == 5 ? '某人喜欢的音乐' : '歌单$id',
  'trackCount': 10,
  'playCount': 100,
  'specialType': special,
  'creator': {'userId': creator, 'nickname': '用户$creator'},
};

/// [artistId] 不为空时账号绑定了这个歌手。
MockClient _client({String? artistId, bool publicRecord = true}) => MockClient((r) async {
  final path = r.url.path;
  if (path.startsWith('/api/v1/user/detail/')) {
    return _json({
      'code': 200,
      'level': 8,
      'listenSongs': 1234,
      'peopleCanSeeMyPlayRecord': publicRecord,
      'profile': {
        'userId': 100,
        'nickname': '某人',
        'signature': '签名在此',
        'follows': 3,
        'followeds': 45,
        'artistId': ?(artistId == null ? null : int.parse(artistId)),
        'description': ?(artistId == null ? null : '唱作音乐人某人'),
      },
    });
  }
  if (path == '/api/v1/artist/12') {
    return _json({
      'code': 200,
      'artist': {
        'id': 12,
        'name': '某歌手',
        'musicSize': 20,
        'albumSize': 2,
        'accountId': 100,
        'briefDesc': '简介',
      },
      'hotSongs': [for (var i = 1; i <= 5; i++) _song(i)],
    });
  }
  if (path == '/api/event/get/100') {
    return _json({
      'code': 200,
      'more': false,
      'lasttime': 1,
      'events': [
        {
          'id': 55,
          'type': 18,
          'eventTime': 1700000000000,
          'user': {'userId': 100, 'nickname': '某人'},
          'json': jsonEncode({'msg': '今天听这首', 'song': _song(3)}),
          'info': {'likedCount': 2, 'commentCount': 1, 'threadId': 'A_EV_2_55_100'},
        },
      ],
    });
  }
  if (path == '/api/user/getfollows/100') {
    return _json({
      'code': 200,
      'more': false,
      'follow': [
        {'userId': 300, 'nickname': '被关注的人', 'signature': '你好', 'followed': true},
      ],
    });
  }
  if (path == '/api/user/playlist') {
    return _json({
      'code': 200,
      'playlist': [
        _playlist(1, 100, special: 5),
        for (var i = 2; i <= 6; i++) _playlist(i, 100),
        _playlist(7, 200),
      ],
    });
  }
  return _json({'code': 200});
});

Future<void> _pump(WidgetTester tester, MockClient client, Widget page) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final f = await fakeServices(client: client);
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
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('a plain user has no tabs, only taste and playlists', (tester) async {
    await _pump(tester, _client(publicRecord: false), const UserPage(userId: 100));
    // 动态已经砍掉，普通用户只剩主页一页，不显示标签栏。
    expect(find.text('主页'), findsNothing);
    expect(find.text('动态'), findsNothing);
    expect(find.text('全部歌曲'), findsNothing);
    expect(find.text('某人'), findsWidgets);
    expect(find.textContaining('粉丝 45'), findsOneWidget);
    expect(find.text('签名在此'), findsOneWidget);
    expect(find.text('音乐品味'), findsOneWidget);
    expect(find.text('TA的听歌排行'), findsOneWidget);
    expect(find.text('TA 没有公开听歌排行'), findsOneWidget);
    expect(find.text('TA喜欢的音乐'), findsOneWidget);
    // 创建了 5 个，只显示前 3 个，可以查看全部。
    expect(find.text('TA创建的歌单（5）'), findsOneWidget);
    expect(find.text('歌单2'), findsOneWidget);
    expect(find.text('歌单4'), findsOneWidget);
    expect(find.text('歌单5'), findsNothing);
    expect(find.text('TA收藏的歌单（1）'), findsOneWidget);
    expect(find.text('歌单7'), findsOneWidget);
    expect(find.text('TA的热门作品'), findsNothing);

    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();
    expect(find.text('歌单6'), findsOneWidget);
  });

  testWidgets('tapping the follow count opens the follow list', (tester) async {
    await _pump(tester, _client(), const UserPage(userId: 100));
    await tester.tap(find.textContaining('关注 3'));
    await tester.pumpAndSettle();
    expect(find.text('被关注的人'), findsOneWidget);
    expect(find.text('你好'), findsOneWidget);
    expect(find.text('已关注'), findsOneWidget);
  });

  testWidgets('an artist entry merges the bound account and adds the works tabs', (tester) async {
    await _pump(tester, _client(artistId: '12'), const UserPage(artist: ArtistRef('12', '某歌手')));
    expect(find.text('主页'), findsOneWidget);
    expect(find.text('全部歌曲'), findsOneWidget);
    expect(find.text('专辑'), findsOneWidget);
    expect(find.text('唱作音乐人某人'), findsOneWidget);
    expect(find.text('TA的热门作品'), findsOneWidget);
    expect(find.text('热歌3'), findsOneWidget);
    expect(find.text('热歌4'), findsNothing);
    expect(find.text('TA创建的歌单（5）'), findsOneWidget);
  });

  testWidgets('a user entry with a bound artist also shows the works tabs', (tester) async {
    await _pump(tester, _client(artistId: '12'), const UserPage(userId: 100));
    expect(find.text('全部歌曲'), findsOneWidget);
    expect(find.text('TA的热门作品'), findsOneWidget);
  });

  test('userDetail parses profile, artist binding and play record privacy', () async {
    final f = await fakeServices(client: _client(artistId: '12', publicRecord: false));
    final u = await f.services.api.userDetail(100);
    expect(u.nickname, '某人');
    expect(u.artistId, '12');
    expect(u.level, 8);
    expect(u.listenSongs, 1234);
    expect(u.playRecordPublic, isFalse);
    final a = await f.services.api.artistDetail('12');
    expect(a.artist.accountId, 100);
  });
}
