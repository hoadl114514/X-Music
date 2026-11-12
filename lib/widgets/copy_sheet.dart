import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app.dart';
import '../data/models.dart';
import '../theme/app_theme.dart';
import 'free_copy_page.dart';

/// 复制到剪贴板并提示。
Future<void> copyText(String text, {String? label}) async {
  await Clipboard.setData(ClipboardData(text: text));
  AppScope.toast(label == null ? '已复制' : '已复制$label');
}

/// 长按歌名 / 歌手时弹出：选择复制歌名、歌手（多位歌手可以单独复制某一位）、专辑或「歌名 - 歌手」。
Future<void> showCopySongSheet(BuildContext context, Song song) {
  final artistNames = song.artists.isNotEmpty
      ? [for (final a in song.artists) a.name]
      : song.artist.split(' / ').where((e) => e.isNotEmpty).toList();
  final options = <({IconData icon, String label, String text})>[
    (icon: Icons.music_note_rounded, label: '歌名', text: song.title),
    if (song.artist.isNotEmpty)
      (icon: Icons.person_outline_rounded, label: '歌手', text: song.artist),
    if (artistNames.length > 1)
      for (final n in artistNames) (icon: Icons.person_outline_rounded, label: '歌手', text: n),
    if (song.album.isNotEmpty) (icon: Icons.album_outlined, label: '专辑', text: song.album),
    if (song.artist.isNotEmpty)
      (icon: Icons.queue_music_rounded, label: '歌名 - 歌手', text: '${song.title} - ${song.artist}'),
  ];
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceHigh,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('复制', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final o in options)
              ListTile(
                leading: Icon(o.icon, color: AppColors.textPrimary),
                title: Text(o.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('复制${o.label}'),
                onTap: () {
                  Navigator.of(context).pop();
                  copyText(o.text, label: o.label);
                },
              ),
            freeCopyTile(
              context,
              [song.title, song.artist, song.album].where((e) => e.isNotEmpty).join('\n'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

/// 长按私信、动态等整段文字时弹出：复制全部，或进入自由复制选一部分。
Future<void> showTextCopySheet(BuildContext context, String text, {required String label}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceHigh,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.copy_rounded, color: AppColors.textPrimary),
            title: Text('复制$label'),
            onTap: () {
              Navigator.of(sheet).pop();
              copyText(text, label: label);
            },
          ),
          freeCopyTile(sheet, text, label: label),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// 底部弹窗里的「自由复制」一项：关掉弹窗，打开自由复制页。
Widget freeCopyTile(BuildContext sheet, String text, {String? label}) => ListTile(
  leading: const Icon(Icons.text_fields_rounded, color: AppColors.textPrimary),
  title: const Text('自由复制'),
  subtitle: const Text('选择任意一段文字复制'),
  onTap: () {
    final nav = Navigator.of(sheet);
    nav.pop();
    FreeCopyPage.open(nav.context, text, label: label);
  },
);
