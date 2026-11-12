import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netease_client/widgets/free_copy_page.dart';

void main() {
  testWidgets('free copy copies the selected part, or everything when nothing is selected', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: FreeCopyPage(text: '第一句歌词\n第二句歌词', label: '歌词'),
      ),
    );
    expect(find.text('未选择，复制全部'), findsOneWidget);

    await tester.tap(find.text('复制全部'));
    await tester.pump();
    expect(clipboard, '第一句歌词\n第二句歌词');

    // 选中「第二句」三个字。
    final field = tester.widget<TextField>(find.byKey(const Key('free-copy-text')));
    field.controller!.selection = const TextSelection(baseOffset: 6, extentOffset: 9);
    await tester.pump();
    expect(find.text('已选 3 字'), findsOneWidget);

    await tester.tap(find.text('复制所选'));
    await tester.pump();
    expect(clipboard, '第二句');

    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(find.text('已选 11 字'), findsOneWidget);
  });
}
