import 'package:flutter/material.dart';

import '../app/app.dart';
import '../data/models.dart';
import '../theme/app_theme.dart';

/// 歌词来源：拖动调整自动获取的先后顺序，开关决定是否参与自动获取。
class LyricSourcesPage extends StatelessWidget {
  const LyricSourcesPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LyricSourcesPage()));

  static const _descriptions = {
    LyricSource.netease: '网易云自带歌词，逐字或逐行',
    LyricSource.amll: 'AMLL 社区逐字歌词，按网易云歌曲 id 精确对应',
    LyricSource.qq: 'QQ 音乐逐字歌词，按歌名、歌手、时长搜索匹配',
  };

  /// 顺序摘要，用在设置页，比如「网易云 → AMLL → QQ 音乐」。
  static String summary(List<LyricSource> sources) => sources.map((s) => s.label).join(' → ');

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return Scaffold(
      appBar: AppBar(title: const Text('歌词来源')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final order = settings.lyricSourceOrder;
          final off = settings.disabledLyricSources;
          final enabledCount = order.where((s) => !off.contains(s)).length;
          return ReorderableListView(
            buildDefaultDragHandles: false,
            header: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                '播放时从上往下依次尝试，取到歌词就停。拖动右侧把手调整顺序；关闭的来源不参与自动获取，'
                '但在播放页「更多」里仍可手动切换。',
                style: TextStyle(color: context.colors.textSecondary, height: 1.4),
              ),
            ),
            onReorderItem: (from, to) {
              final next = [...order];
              next.insert(to, next.removeAt(from));
              settings.lyricSourceOrder = next;
            },
            children: [
              for (final (i, s) in order.indexed)
                ListTile(
                  key: ValueKey(s),
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: off.contains(s)
                        ? context.colors.surfaceHigh
                        : context.colors.accent.withValues(alpha: 0.18),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: off.contains(s)
                            ? context.colors.textSecondary
                            : context.colors.accent,
                      ),
                    ),
                  ),
                  title: Text(s.label),
                  subtitle: Text(_descriptions[s] ?? ''),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: !off.contains(s),
                        // 至少保留一个打开的来源。
                        onChanged: !off.contains(s) && enabledCount <= 1
                            ? null
                            : (v) => settings.setLyricSourceEnabled(s, v),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_handle_rounded, semanticLabel: '拖动排序'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
