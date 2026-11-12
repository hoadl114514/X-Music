import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'copy_sheet.dart';

/// 自由复制：整段文字放进可选择的文本框，用户拖动选择任意一段复制。
/// 选中了文字时底部按钮复制选中部分，没选时复制全部。
class FreeCopyPage extends StatefulWidget {
  const FreeCopyPage({super.key, required this.text, this.title = '自由复制', this.label});

  final String text;
  final String title;

  /// 复制成功提示里的名称，例如「歌词」「评论」。
  final String? label;

  static Future<void> open(
    BuildContext context,
    String text, {
    String title = '自由复制',
    String? label,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FreeCopyPage(text: text, title: title, label: label),
    ),
  );

  @override
  State<FreeCopyPage> createState() => _FreeCopyPageState();
}

class _FreeCopyPageState extends State<FreeCopyPage> {
  late final _controller = TextEditingController(text: widget.text);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  TextSelection get _selection => _controller.selection;
  bool get _hasSelection => _selection.isValid && !_selection.isCollapsed;

  void _selectAll() {
    _focus.requestFocus();
    _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
  }

  void _copy() {
    final text = _hasSelection ? _selection.textInside(_controller.text) : _controller.text;
    copyText(text, label: widget.label);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _hasSelection ? _selection.textInside(_controller.text).characters.length : 0;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(widget.title),
        actions: [TextButton(onPressed: _selectAll, child: const Text('全选'))],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '长按或双击文字开始选择，拖动两端调整范围',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
          ),
          Expanded(
            child: TextField(
              key: const Key('free-copy-text'),
              controller: _controller,
              focusNode: _focus,
              readOnly: true,
              showCursor: false,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              enableInteractiveSelection: true,
              style: const TextStyle(fontSize: 17, height: 1.6, color: AppColors.textPrimary),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(20, 8, 20, 24),
              ),
              contextMenuBuilder: (context, state) => AdaptiveTextSelectionToolbar.buttonItems(
                anchors: state.contextMenuAnchors,
                buttonItems: [
                  ContextMenuButtonItem(
                    label: '复制',
                    onPressed: () {
                      _copy();
                      state.hideToolbar();
                    },
                  ),
                  if (_selection.textInside(_controller.text).length != _controller.text.length)
                    ContextMenuButtonItem(
                      label: '全选',
                      onPressed: () => state.selectAll(SelectionChangedCause.toolbar),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surfaceHigh,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _hasSelection ? '已选 $selected 字' : '未选择，复制全部',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(_hasSelection ? '复制所选' : '复制全部'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.onAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
