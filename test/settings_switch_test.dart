import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/app/app.dart';
import 'package:netease_client/pages/settings_page.dart';
import 'package:netease_client/state/account_controller.dart';
import 'package:netease_client/state/player_controller.dart';

import 'support/fakes.dart';

void main() {
  // 音频输出那几项是 const 子组件，以前点了开关不变，要退出重进才显示。
  testWidgets('output switches update right after tapping', (tester) async {
    // 窗口拉高，整个设置页一屏放下，不用滚动。
    tester.view
      ..physicalSize = const Size(800, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await fakeServices();
    await tester.pumpWidget(
      AppScope(
        services: f.services,
        child: AccountScope(
          controller: f.services.account,
          child: PlayerScope(
            controller: f.services.player,
            child: const MaterialApp(home: Scaffold(body: SettingsPage())),
          ),
        ),
      ),
    );
    await tester.pump();
    final tile = find.widgetWithText(SwitchListTile, '与其他应用同时播放');
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    await tester.tap(find.descendant(of: tile, matching: find.byType(Switch)));
    await tester.pump();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(f.services.settings.mixWithOthers, isTrue);
  });
}
