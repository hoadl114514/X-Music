import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netease_client/app/update_checker.dart';

import 'support/fakes.dart';

void main() {
  test('compareVersions orders numbers and pre-releases', () {
    expect(compareVersions('v0.1.0', '0.0.9-alpha'), greaterThan(0));
    expect(compareVersions('v0.1.0', '0.1.0'), 0);
    expect(compareVersions('v0.1.0', '0.1.0-alpha'), greaterThan(0));
    expect(compareVersions('v0.1.0-beta', '0.1.0'), lessThan(0));
    expect(compareVersions('v0.10.0', '0.9.0'), greaterThan(0));
    expect(compareVersions('v1.0', '1.0.0'), 0);
    expect(compareVersions('v0.1.2.1', '0.1.2'), greaterThan(0));
    expect(compareVersions('v0.1.2', '0.1.2.1'), lessThan(0));
    expect(compareVersions('v0.1.3', '0.1.2.1'), greaterThan(0));
    expect(compareVersions('v0.1.2.0', '0.1.2'), 0);
  });

  test('newerRelease returns the latest release only when it is newer', () async {
    final settings = await testSettings();
    UpdateChecker checker(String tag) => UpdateChecker(
      settings: settings,
      client: MockClient(
        // 中文要按 UTF-8 发，http.Response(String) 默认 latin1。
        (_) async => http.Response.bytes(
          utf8.encode(
            '{"tag_name":"$tag","name":"X-Music $tag","body":"更新内容","html_url":"https://example.com/$tag"}',
          ),
          200,
        ),
      ),
    );

    final newer = await checker('v99.0.0').newerRelease();
    expect(newer?.tag, 'v99.0.0');
    expect(newer?.url, 'https://example.com/v99.0.0');
    expect(newer?.notes, '更新内容');
    expect(await checker('v0.0.1').newerRelease(), isNull);
  });

  test('fetchLatest returns null on HTTP errors', () async {
    final checker = UpdateChecker(
      settings: await testSettings(),
      client: MockClient((_) async => http.Response('{"message":"Not Found"}', 404)),
    );
    expect(await checker.fetchLatest(), isNull);
  });
}
