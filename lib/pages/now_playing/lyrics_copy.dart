import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/copy_sheet.dart';
import '../../widgets/free_copy_page.dart';

/// 把选中的歌词行拼成文本：每行原文，后面按需跟翻译、罗马音。
String lyricsText(Iterable<LyricLine> lines, {bool translation = false, bool romaji = false}) => [
  for (final l in lines)
    [l.text, if (translation) ?l.translation, if (romaji) ?l.romaji].join('\n'),
].join('\n');

/// 长按某一行歌词：复制这一行，或进入批量选择。
Future<void> showLyricLineActions(BuildContext context, Song song, Lyrics lyrics, int index) {
  final line = lyrics.lines[index];
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceHigh,
    showDragHandle: true,
    builder: (sheet) {
      void copy(String text) {
        Navigator.of(sheet).pop();
        copyText(text, label: '歌词');
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                line.text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: AppColors.textPrimary),
              title: const Text('复制这句'),
              onTap: () => copy(line.text),
            ),
            if (line.translation != null || line.romaji != null)
              ListTile(
                leading: const Icon(Icons.translate_rounded, color: AppColors.textPrimary),
                title: const Text('复制这句（含翻译 / 罗马音）'),
                onTap: () => copy(lyricsText([line], translation: true, romaji: true)),
              ),
            ListTile(
              leading: const Icon(Icons.checklist_rounded, color: AppColors.textPrimary),
              title: const Text('批量复制'),
              subtitle: const Text('选择多句歌词一起复制'),
              onTap: () {
                final nav = Navigator.of(sheet);
                nav.pop();
                LyricsCopyPage.open(nav.context, song: song, lyrics: lyrics, initial: index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.subject_rounded, color: AppColors.textPrimary),
              title: const Text('复制全部歌词'),
              onTap: () => copy(lyricsText(lyrics.lines)),
            ),
            freeCopyTile(
              sheet,
              lyricsText(lyrics.lines, translation: lyrics.hasTranslation),
              label: '歌词',
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// 批量复制歌词：勾选若干行后一起复制。点一行切换选中；长按一行把它和上次点的那行之间全部选中。
class LyricsCopyPage extends StatefulWidget {
  const LyricsCopyPage({super.key, required this.song, required this.lyrics, this.initial});

  final Song song;
  final Lyrics lyrics;

  /// 进来时预先选中的行。
  final int? initial;

  static Future<void> open(
    BuildContext context, {
    required Song song,
    required Lyrics lyrics,
    int? initial,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LyricsCopyPage(song: song, lyrics: lyrics, initial: initial),
    ),
  );

  @override
  State<LyricsCopyPage> createState() => _LyricsCopyPageState();
}

class _LyricsCopyPageState extends State<LyricsCopyPage> {
  late final Set<int> _selected = {?widget.initial};
  late int? _anchor = widget.initial;
  late bool _translation = widget.lyrics.hasTranslation;
  bool _romaji = false;

  List<LyricLine> get _lines => widget.lyrics.lines;
  bool get _allSelected => _selected.length == _lines.length;

  void _toggle(int i) => setState(() {
    if (!_selected.remove(i)) _selected.add(i);
    _anchor = i;
  });

  void _selectRange(int i) => setState(() {
    final a = _anchor ?? i;
    for (var k = a < i ? a : i; k <= (a < i ? i : a); k++) {
      _selected.add(k);
    }
    _anchor = i;
  });

  void _copy() {
    final picked = (_selected.toList()..sort()).map((i) => _lines[i]);
    copyText(
      lyricsText(picked, translation: _translation, romaji: _romaji),
      label: ' ${_selected.length} 句歌词',
    );
    Navigator.of(context).pop();
  }

  /// 把选中的几句（没选就是全部）放进自由复制页，再挑其中一段。
  void _freeCopy() {
    final picked = _selected.isEmpty ? _lines : (_selected.toList()..sort()).map((i) => _lines[i]);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => FreeCopyPage(
          text: lyricsText(picked, translation: _translation, romaji: _romaji),
          label: '歌词',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.lyrics;
    return Scaffold(
      appBar: AppBar(
        title: Text(_selected.isEmpty ? '选择歌词' : '已选 ${_selected.length} 句'),
        actions: [
          IconButton(
            tooltip: '自由复制',
            onPressed: _freeCopy,
            icon: const Icon(Icons.text_fields_rounded),
          ),
          TextButton(
            onPressed: () => setState(() {
              if (_allSelected) {
                _selected.clear();
              } else {
                _selected.addAll(List.generate(_lines.length, (i) => i));
              }
            }),
            child: Text(_allSelected ? '全不选' : '全选'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _lines.length,
              itemBuilder: (context, i) {
                final line = _lines[i];
                final on = _selected.contains(i);
                return InkWell(
                  onTap: () => _toggle(i),
                  onLongPress: () => _selectRange(i),
                  child: Container(
                    color: on ? AppColors.accent.withValues(alpha: 0.12) : null,
                    padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
                    child: Row(
                      children: [
                        Checkbox(value: on, onChanged: (_) => _toggle(i)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.text.isEmpty ? '（空行）' : line.text,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: line.text.isEmpty
                                      ? AppColors.textMuted
                                      : AppColors.textPrimary,
                                ),
                              ),
                              if (line.translation case final t? when _translation)
                                Text(
                                  t,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              if (line.romaji case final r? when _romaji)
                                Text(
                                  r,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surfaceHigh,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
              child: Row(
                children: [
                  if (lyrics.hasTranslation)
                    FilterChip(
                      label: const Text('翻译'),
                      selected: _translation,
                      onSelected: (v) => setState(() => _translation = v),
                    ),
                  if (lyrics.hasRomaji) ...[
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('罗马音'),
                      selected: _romaji,
                      onSelected: (v) => setState(() => _romaji = v),
                    ),
                  ],
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _selected.isEmpty ? null : _copy,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text('复制${_selected.isEmpty ? '' : '（${_selected.length}）'}'),
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
