import 'package:flutter/material.dart';

import '../data/format.dart';
import '../data/models.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../pages/library/song_actions.dart';
import 'copy_sheet.dart';
import 'cover_art.dart';

/// 歌曲列表的一行。正在播放的那首标题高亮；长按选择复制歌名或歌手。
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.index,
    this.trailing,
    this.onRemove,
    this.selected,
  });

  final Song song;

  /// 点这一行。多选时是勾选 / 取消勾选。
  final VoidCallback onTap;

  /// 「更多」菜单里的「从歌单中删除」；为 null 时不显示这一项。
  final VoidCallback? onRemove;

  /// 多选模式下是否选中；为 null 表示不在多选模式（显示「更多」按钮）。
  final bool? selected;

  /// 序号（从 1 开始）。为 null 时不显示。
  final int? index;

  /// 替代右侧时长显示的文字（如播放次数）。
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final playing = PlayerScope.of(context).current?.id == song.id;
    final titleColor = playing ? AppColors.accent : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      onLongPress: selected == null ? () => showCopySongSheet(context, song) : null,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, selected == null ? 0 : 16, 8),
        child: Row(
          children: [
            if (selected case final checked?)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: checked ? AppColors.accent : AppColors.textMuted,
                ),
              ),
            if (index != null)
              SizedBox(
                width: 32,
                child: Text(
                  '$index',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            SizedBox(
              width: 44,
              child: CoverArt(
                palette: song.palette,
                seed: song.id,
                imageUrl: song.coverUrl,
                radius: 4,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: song.title,
                      children: [
                        if (song.subtitle case final s?)
                          TextSpan(
                            text: '  $s',
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: titleColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [song.artist, if (song.album.isNotEmpty) song.album].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              trailing ?? formatDuration(song.duration),
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            if (selected == null)
              IconButton(
                tooltip: '更多',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
                onPressed: () => showSongActions(context, song, onRemove: onRemove),
              ),
          ],
        ),
      ),
    );
  }
}
