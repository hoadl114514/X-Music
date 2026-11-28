import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../listen_together_page.dart';
import '../../app/app.dart';
import '../../data/models.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../state/account_controller.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/playlist_card.dart';
import '../login_page.dart';
import '../music/nav.dart';
import '../../widgets/copy_sheet.dart';
import 'lyrics_copy.dart';

Future<void> _sheet(BuildContext context, Widget child) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: context.colors.surfaceHigh,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => child,
);

/// 播放页 / 歌词页右上角「更多」：音质、歌词来源与显示、歌词偏移、歌曲操作。
/// [onWiki] 给了时多一项「歌曲百科」，点了收起菜单再调用它。
Future<void> showSongMenu(BuildContext context, {VoidCallback? onWiki}) =>
    _sheet(context, _SongMenu(onWiki: onWiki));

/// 音质选择：只列出当前歌曲提供的档位。
Future<void> showQualitySheet(BuildContext context) => _sheet(context, const _QualitySheet());

/// 播放队列。
Future<void> showQueueSheet(BuildContext context) => _sheet(context, const _QueueSheet());

/// 收藏到自己的歌单。
Future<void> showAddToPlaylistSheet(BuildContext context, Song song) {
  if (!AccountScope.read(context).isLoggedIn) return LoginPage.open(context);
  return _sheet(context, _AddToPlaylistSheet(song: song));
}

/// 定时关闭。
Future<void> showSleepTimerSheet(BuildContext context) => _sheet(context, const _SleepSheet());

class _AddToPlaylistSheet extends StatelessWidget {
  const _AddToPlaylistSheet({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    final own = account.addablePlaylists;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.5,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('收藏到歌单', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: own.isEmpty
                  ? Center(
                      child: Text(
                        '还没有自己创建的歌单',
                        style: TextStyle(color: context.colors.textSecondary),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final p in own)
                          ListTile(
                            leading: SizedBox(
                              width: 44,
                              child: CoverArt(
                                palette: p.palette,
                                seed: p.id,
                                imageUrl: p.coverUrl,
                                fallbackImage: playlistCoverFallback(context, p),
                                radius: 4,
                              ),
                            ),
                            title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${p.trackCount} 首'),
                            onTap: () async {
                              Navigator.of(context).pop();
                              try {
                                await account.addToPlaylist(p, song);
                                AppScope.toast('已收藏到「${p.name}」');
                              } catch (e) {
                                AppScope.toast('收藏失败：$e');
                              }
                            },
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SleepSheet extends StatelessWidget {
  const _SleepSheet();

  static const _options = [15, 30, 45, 60, 90];

  /// 例如「1 小时 20 分钟」「45 分钟」。
  static String describe(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    return [if (h > 0) '$h 小时', if (m > 0 || h == 0) '$m 分钟'].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final nav = Navigator.of(context);
    void set(Duration? d) {
      player.setSleepTimer(d);
      AppScope.toast(d == null ? '已取消定时关闭' : '${describe(d)}后暂停播放');
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in _options)
            ListTile(
              title: Text('$m 分钟'),
              onTap: () {
                nav.pop();
                set(Duration(minutes: m));
              },
            ),
          ListTile(
            title: const Text('自定义…'),
            onTap: () async {
              nav.pop();
              final d = await _pickCustom(nav.context);
              if (d != null) set(d);
            },
          ),
          if (player.sleepAt != null)
            ListTile(
              title: Text('取消定时', style: TextStyle(color: context.colors.accent)),
              onTap: () {
                nav.pop();
                set(null);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 选小时和分钟，最短 1 分钟。取消时返回 null。
  static Future<Duration?> _pickCustom(BuildContext context) {
    var picked = const Duration(minutes: 30);
    return showDialog<Duration>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义定时关闭'),
        content: SizedBox(
          height: 216,
          width: 300,
          child: CupertinoTheme(
            data: CupertinoThemeData(
              brightness: Theme.of(context).brightness,
              textTheme: CupertinoTextThemeData(
                pickerTextStyle: TextStyle(fontSize: 21, color: context.colors.textPrimary),
              ),
            ),
            child: CupertinoTimerPicker(
              mode: CupertinoTimerPickerMode.hm,
              initialTimerDuration: picked,
              onTimerDurationChanged: (d) => picked = d,
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              picked < const Duration(minutes: 1) ? const Duration(minutes: 1) : picked,
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _SongMenu extends StatelessWidget {
  const _SongMenu({this.onWiki});

  final VoidCallback? onWiki;

  static const _step = Duration(milliseconds: 500);

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final song = player.current;
    if (song == null) return const SizedBox.shrink();
    final settings = AppScope.of(context).settings;
    final lyrics = player.lyrics;
    final offset = player.lyricOffset.inMilliseconds / 1000;
    final active = player.activeLyricIndex;

    // 先关掉菜单再执行，避免菜单盖在新页面上。
    void then(Future<void> Function() action) {
      Navigator.of(context).pop();
      action();
    }

    final sleepAt = player.sleepAt;
    final api = AppScope.of(context).api;

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: SizedBox(
                  width: 48,
                  child: CoverArt(
                    palette: song.palette,
                    seed: song.id,
                    imageUrl: song.coverUrl,
                    radius: 4,
                  ),
                ),
                title: Text(song.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(song.artist),
                trailing: IconButton(
                  tooltip: '复制歌名 / 歌手',
                  icon: Icon(Icons.copy_rounded, color: context.colors.textSecondary),
                  onPressed: () {
                    final nav = Navigator.of(context);
                    nav.pop();
                    showCopySongSheet(nav.context, song);
                  },
                ),
                onLongPress: () => showCopySongSheet(context, song),
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.graphic_eq_rounded, color: context.colors.textPrimary),
                title: const Text('音质'),
                subtitle: Text(
                  player.qualities.isEmpty ? '暂无可选音质' : '${player.qualities.length} 档可选',
                ),
                trailing: Text(
                  player.quality?.label ?? '—',
                  style: TextStyle(color: context.colors.accent),
                ),
                onTap: player.qualities.isEmpty ? null : () => showQualitySheet(context),
              ),
              ListTile(
                leading: Icon(Icons.lyrics_outlined, color: context.colors.textPrimary),
                title: const Text('歌词来源'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.lyricsLoading
                          ? '加载中…'
                          : lyrics.isEmpty
                          ? '暂无歌词'
                          : [
                              lyrics.source!.label,
                              lyrics.wordSynced ? '逐字' : '逐行',
                              if (lyrics.hasTranslation) '翻译',
                              if (lyrics.hasRomaji) '罗马音',
                            ].join(' · '),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<LyricSource>(
                      segments: [
                        for (final s in LyricSource.values)
                          ButtonSegment(value: s, label: Text(s.label)),
                      ],
                      selected: {?lyrics.source},
                      emptySelectionAllowed: true,
                      showSelectedIcon: false,
                      onSelectionChanged: (v) {
                        if (v.isNotEmpty) player.setLyricSource(v.first);
                      },
                    ),
                  ],
                ),
              ),
              if (lyrics.hasTranslation)
                SwitchListTile(
                  secondary: Icon(Icons.translate_rounded, color: context.colors.textPrimary),
                  title: const Text('显示翻译'),
                  value: settings.showTranslation,
                  onChanged: (v) => settings.showTranslation = v,
                ),
              if (lyrics.hasRomaji)
                SwitchListTile(
                  secondary: Icon(Icons.abc_rounded, color: context.colors.textPrimary),
                  title: const Text('显示罗马音'),
                  value: settings.showRomaji,
                  onChanged: (v) => settings.showRomaji = v,
                ),
              ListTile(
                leading: Icon(Icons.av_timer_rounded, color: context.colors.textPrimary),
                title: const Text('歌词偏移'),
                subtitle: const Text('歌词和声音对不上时调整'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => player.adjustLyricOffset(-_step),
                      tooltip: '歌词延后 0.5s',
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    GestureDetector(
                      onTap: player.resetLyricOffset,
                      child: SizedBox(
                        width: 48,
                        child: Text(
                          offset == 0
                              ? '0s'
                              : '${offset > 0 ? '+' : ''}${offset.toStringAsFixed(1)}s',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => player.adjustLyricOffset(_step),
                      tooltip: '歌词提前 0.5s',
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: Icon(Icons.copy_rounded, color: context.colors.textPrimary),
                title: const Text('复制当前歌词'),
                enabled: active >= 0,
                onTap: active < 0
                    ? null
                    : () {
                        final line = lyrics.lines[active];
                        Clipboard.setData(
                          ClipboardData(
                            text: [line.text, ?line.translation, ?line.romaji].join('\n'),
                          ),
                        );
                        Navigator.of(context).pop();
                        AppScope.toast('已复制歌词');
                      },
              ),
              ListTile(
                leading: Icon(Icons.checklist_rounded, color: context.colors.textPrimary),
                title: const Text('批量复制歌词'),
                subtitle: const Text('也可以在歌词上长按'),
                enabled: !lyrics.isEmpty,
                onTap: lyrics.isEmpty
                    ? null
                    : () {
                        final nav = Navigator.of(context);
                        nav.pop();
                        LyricsCopyPage.open(
                          nav.context,
                          song: song,
                          lyrics: lyrics,
                          initial: active >= 0 ? active : null,
                        );
                      },
              ),
              const Divider(),
              if (player.isRadio)
                ListTile(
                  leading: Icon(Icons.thumb_down_outlined, color: context.colors.textPrimary),
                  title: const Text('不喜欢这首'),
                  subtitle: const Text('私人 FM 不再推荐，并跳到下一首'),
                  onTap: () => then(() async {
                    try {
                      await api.fmTrash(song.id);
                    } catch (e) {
                      AppScope.toast('操作失败：$e');
                      return;
                    }
                    await player.skipAndRemoveCurrent();
                  }),
                ),
              ListTile(
                leading: Icon(Icons.playlist_add_rounded, color: context.colors.textPrimary),
                title: const Text('收藏到歌单'),
                onTap: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  showAddToPlaylistSheet(nav.context, song);
                },
              ),
              if (onWiki case final wiki?)
                ListTile(
                  leading: Icon(Icons.auto_stories_outlined, color: context.colors.textPrimary),
                  title: const Text('歌曲百科'),
                  subtitle: const Text('曲风、标签、相似歌曲；在播放页向左滑也能看到'),
                  onTap: () {
                    Navigator.of(context).pop();
                    wiki();
                  },
                ),
              _ListenTogetherTile(
                onTap: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  ListenTogetherPage.open(nav.context);
                },
              ),
              ListTile(
                leading: Icon(Icons.person_outline_rounded, color: context.colors.textPrimary),
                title: const Text('查看歌手'),
                subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                enabled: song.artists.isNotEmpty,
                onTap: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  openSongArtist(nav.context, song);
                },
              ),
              ListTile(
                leading: Icon(Icons.album_outlined, color: context.colors.textPrimary),
                title: const Text('查看专辑'),
                subtitle: Text(song.album, maxLines: 1, overflow: TextOverflow.ellipsis),
                enabled: song.albumId != null,
                onTap: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  openAlbum(nav.context, song.albumId!, name: song.album);
                },
              ),
              ListTile(
                leading: Icon(Icons.bedtime_outlined, color: context.colors.textPrimary),
                title: const Text('定时关闭'),
                trailing: sleepAt == null
                    ? null
                    : Text(
                        '${sleepAt.hour.toString().padLeft(2, '0')}:'
                        '${sleepAt.minute.toString().padLeft(2, '0')} 暂停',
                        style: TextStyle(color: context.colors.accent),
                      ),
                onTap: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  showSleepTimerSheet(nav.context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _QualitySheet extends StatefulWidget {
  const _QualitySheet();

  @override
  State<_QualitySheet> createState() => _QualitySheetState();
}

class _QualitySheetState extends State<_QualitySheet> {
  @override
  void initState() {
    super.initState();
    // 位深要读文件头，打开列表时才去读。
    unawaited(PlayerScope.read(context).probeBitDepths());
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    // 高音质排在上面。
    final options = player.qualities.reversed.toList();
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '只显示这首歌提供的音质。账号权益不足时会自动降到可用的最高档。',
              style: TextStyle(fontSize: 12, color: context.colors.textMuted),
            ),
          ),
          for (final info in options)
            ListTile(
              title: Text(info.quality.label),
              subtitle: Text(_describe(info, player.bitDepthOf(info.quality))),
              trailing: info.quality == player.quality
                  ? Icon(Icons.check_rounded, color: context.colors.accent)
                  : null,
              onTap: () {
                Navigator.of(context).pop();
                player.setQuality(info.quality);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static String _describe(QualityInfo i, int? bits) => [
    if (i.bitrate > 0) '${(i.bitrate / 1000).round()} kbps',
    if (i.sampleRate case final sr? when sr > 0)
      '${(sr / 1000).toStringAsFixed(sr % 1000 == 0 ? 0 : 1)} kHz',
    if (bits != null) '$bits bit',
    if (i.size > 0) '${(i.size / 1024 / 1024).toStringAsFixed(1)} MB',
  ].join(' · ');
}

class _QueueSheet extends StatefulWidget {
  const _QueueSheet();

  @override
  State<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<_QueueSheet> {
  static const _itemExtent = 56.0;

  // 打开时让当前歌曲大致在可见区域里。
  late final _scroll = ScrollController(
    initialScrollOffset: (PlayerScope.read(context).index - 2).clamp(0, 1 << 20) * _itemExtent,
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final queue = player.queue;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text(
                    '播放列表（${queue.length}）',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    player.queueTitle,
                    style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                itemExtent: _itemExtent,
                itemCount: queue.length,
                itemBuilder: (context, i) {
                  final s = queue[i];
                  final current = i == player.index;
                  return ListTile(
                    dense: true,
                    title: Text(
                      s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: current ? context.colors.accent : context.colors.textPrimary,
                      ),
                    ),
                    subtitle: Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: current
                        ? Icon(Icons.graphic_eq_rounded, color: context.colors.accent)
                        : null,
                    onTap: () => player.jumpTo(i),
                    onLongPress: () => showCopySongSheet(context, s),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「更多」里的一起听：在房间里时显示人数，点了打开一起听页面。
class _ListenTogetherTile extends StatelessWidget {
  const _ListenTogetherTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final listen = AppScope.of(context).listen;
    return ListenableBuilder(
      listenable: listen,
      builder: (context, _) => ListTile(
        leading: Icon(
          listen.active ? Icons.headphones_rounded : Icons.headphones_outlined,
          color: listen.active ? context.colors.accent : context.colors.textPrimary,
        ),
        title: const Text('一起听'),
        subtitle: Text(listen.active ? '在房间里 · ${listen.users.length} 人' : '开个房间，和好友同步听歌'),
        onTap: onTap,
      ),
    );
  }
}
