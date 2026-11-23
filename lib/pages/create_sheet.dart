import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'library/playlist_editor.dart';
import 'listen_together_page.dart';

/// 底栏「创建」弹出的面板：歌单、共建歌单、一起听。
Future<void> showCreateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheet) {
      void then(Future<void> Function(BuildContext context) action) {
        final nav = Navigator.of(sheet);
        nav.pop();
        action(nav.context);
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CreateItem(
                icon: Icons.queue_music_rounded,
                title: '歌单',
                subtitle: '创建一个新歌单',
                onTap: () => then(showCreatePlaylistDialog),
              ),
              _CreateItem(
                icon: Icons.group_add_rounded,
                title: '共建歌单',
                subtitle: '与好友一起往歌单里加歌',
                onTap: () => then((c) => showCreatePlaylistDialog(c, shared: true)),
              ),
              _CreateItem(
                icon: Icons.headphones_rounded,
                title: '一起听',
                subtitle: '和好友同步听同一首歌',
                onTap: () => then(ListenTogetherPage.open),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _CreateItem extends StatelessWidget {
  const _CreateItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
              child: Icon(icon, color: scheme.onSecondaryContainer, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
