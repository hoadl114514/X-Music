import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/app/app.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('私人 FM 模式菜单在手机屏上能看到全部选项', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await fakeServices();
    await tester.pumpWidget(NeteaseClientApp(services: f.services));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('推荐模式'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final last = tester.getRect(find.text('深夜'));
    expect(last.bottom, lessThanOrEqualTo(860));
  });
}
