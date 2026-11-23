import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/api/netease_api.dart';
import 'package:netease_client/data/models.dart';

void main() {
  test('personal FM uses the mode endpoint only for non-default modes', () async {
    final paths = <String>[];
    final api = NeteaseApi(
      client: MockClient((r) async {
        paths.add(r.url.path);
        return http.Response(
          jsonEncode({
            'code': 200,
            'data': [
              {'id': 1, 'name': '一首', 'ar': <Object>[], 'al': <String, Object>{}, 'dt': 1000},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    expect(await api.personalFm(), hasLength(1));
    expect(await api.personalFm(mode: FmMode.exercise), hasLength(1));
    expect(paths, ['/api/v1/radio/get', '/weapi/v1/radio/get']);
    expect(FmMode.fromName('focus'), FmMode.focus);
    expect(FmMode.fromName(null), FmMode.normal);
  });
}
