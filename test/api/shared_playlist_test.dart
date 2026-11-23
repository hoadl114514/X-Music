import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/api/netease_api.dart';

void main() {
  test('specialType 300 marks a shared playlist even before anyone joins', () async {
    // 字段取自真实账号的共享歌单（刚创建，还没有成员）。
    final api = NeteaseApi(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 200,
            'playlist': [
              {'id': 1, 'name': 'test', 'specialType': 300, 'privacy': 0, 'sharedUsers': null},
              {'id': 2, 'name': '普通', 'specialType': 0, 'privacy': 10, 'sharedUsers': null},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final lists = await api.userPlaylists(1);
    expect(lists.first.shared, isTrue);
    expect(lists.first.sharedUsers, isEmpty);
    expect(lists.last.shared, isFalse);
  });
}
