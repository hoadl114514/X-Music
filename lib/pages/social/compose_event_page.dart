import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/netease_api.dart';
import '../../app/app.dart';
import '../../data/models.dart';
import '../../state/account_controller.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/playlist_card.dart';
import '../login_page.dart';

/// 发动态：写一段话，可以附一首歌或一个歌单。
///
/// 网易云的接口只能附一个资源；不附资源时正文不能为空。
class ComposeEventPage extends StatefulWidget {
  const ComposeEventPage({super.key, this.song, this.playlist});

  /// 预先附上的歌 / 歌单（例如从歌曲菜单、歌单页进来）。
  final Song? song;
  final Playlist? playlist;

  /// 打开发动态页，发出去了返回 true。未登录时先去登录。
  static Future<bool> open(BuildContext context, {Song? song, Playlist? playlist}) async {
    if (!AccountScope.read(context).isLoggedIn) {
      await LoginPage.open(context);
      return false;
    }
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ComposeEventPage(song: song, playlist: playlist),
      ),
    );
    return posted ?? false;
  }

  @override
  State<ComposeEventPage> createState() => _ComposeEventPageState();
}

class _ComposeEventPageState extends State<ComposeEventPage> {
  final _text = TextEditingController();
  late Song? _song = widget.song;
  late Playlist? _playlist = widget.playlist;
  bool _busy = false;

  bool get _hasAttachment => _song != null || _playlist != null;
  bool get _canSend => !_busy && (_hasAttachment || _text.text.trim().isNotEmpty);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() => _busy = true);
    final api = AppScope.of(context).api;
    try {
      final msg = _text.text.trim();
      if (_song case final s?) {
        await api.shareEvent(msg, type: ShareType.song, id: s.id);
      } else if (_playlist case final p?) {
        await api.shareEvent(msg, type: ShareType.playlist, id: p.id);
      } else {
        await api.shareEvent(msg);
      }
      AppScope.toast('动态已发布');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      AppScope.toast('发布失败：$e');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickSong() async {
    final s = await Navigator.of(context)
        .push<Song>(MaterialPageRoute(builder: (_) => const _SongPicker()));
    if (s != null && mounted) {
      setState(() {
        _song = s;
        _playlist = null;
      });
    }
  }

  Future<void> _pickPlaylist() async {
    final p = await showModalBottomSheet<Playlist>(
      context: context,
      backgroundColor: AppColors.surfaceHigh,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _PlaylistPicker(),
    );
    if (p != null && mounted) {
      setState(() {
        _playlist = p;
        _song = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = PlayerScope.of(context).current;
    return Scaffold(
      appBar: AppBar(
        title: const Text('发动态'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _canSend ? _send : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
                visualDensity: VisualDensity.compact,
              ),
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('发布'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _text,
            autofocus: true,
            enabled: !_busy,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(hintText: '分享新鲜事…', border: InputBorder.none),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (_song case final s?)
            _Attachment(
              title: s.title,
              subtitle: '单曲 · ${s.artist}',
              cover: CoverArt(palette: s.palette, seed: s.id, imageUrl: s.coverUrl, radius: 4),
              onRemove: _busy ? null : () => setState(() => _song = null),
            )
          else if (_playlist case final p?)
            _Attachment(
              title: p.name,
              subtitle: '歌单 · ${p.trackCount} 首',
              cover: CoverArt(
                palette: p.palette,
                seed: p.id,
                imageUrl: p.coverUrl,
                fallbackImage: playlistCoverFallback(context, p),
                radius: 4,
              ),
              onRemove: _busy ? null : () => setState(() => _playlist = null),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (current != null)
                  ActionChip(
                    avatar: const Icon(Icons.graphic_eq_rounded, size: 18),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        '正在播放：${current.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    onPressed: _busy ? null : () => setState(() => _song = current),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.music_note_rounded, size: 18),
                  label: const Text('添加歌曲'),
                  onPressed: _busy ? null : _pickSong,
                ),
                ActionChip(
                  avatar: const Icon(Icons.queue_music_rounded, size: 18),
                  label: const Text('添加歌单'),
                  onPressed: _busy ? null : _pickPlaylist,
                ),
              ],
            ),
          const SizedBox(height: 16),
          const Text(
            '一条动态只能附一首歌或一个歌单。不附内容时需要写点什么。',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Attachment extends StatelessWidget {
  const _Attachment({
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.onRemove,
  });

  final String title;
  final String subtitle;
  final Widget cover;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardHover,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: ListTile(
        leading: SizedBox(width: 44, height: 44, child: cover),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        trailing: IconButton(
          tooltip: '移除',
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded),
        ),
      ),
    );
  }
}

/// 选一个自己的歌单（创建的和收藏的）。
class _PlaylistPicker extends StatelessWidget {
  const _PlaylistPicker();

  @override
  Widget build(BuildContext context) {
    final list = AccountScope.of(context).playlists;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('选择歌单', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: list.isEmpty
                  ? const Center(
                      child: Text('还没有歌单', style: TextStyle(color: AppColors.textSecondary)),
                    )
                  : ListView(
                      children: [
                        for (final p in list)
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
                            onTap: () => Navigator.of(context).pop(p),
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

/// 搜索一首歌。
class _SongPicker extends StatefulWidget {
  const _SongPicker();

  @override
  State<_SongPicker> createState() => _SongPickerState();
}

class _SongPickerState extends State<_SongPicker> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<Song> _songs = const [];
  bool _loading = false;
  Object? _error;

  /// 防止旧请求的结果覆盖新的。
  int _generation = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    final gen = ++_generation;
    if (q.isEmpty) {
      setState(() {
        _songs = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await AppScope.of(context).api.searchSongs(q);
      if (!mounted || gen != _generation) return;
      setState(() {
        _songs = r.songs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error case final e?) {
      body = Center(
        child: TextButton(onPressed: _search, child: Text('搜索失败，点击重试\n$e')),
      );
    } else if (_songs.isEmpty) {
      body = Center(
        child: Text(
          _query.text.trim().isEmpty ? '输入歌名或歌手' : '没有找到',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    } else {
      body = ListView.builder(
        itemCount: _songs.length,
        itemBuilder: (context, i) {
          final s = _songs[i];
          return ListTile(
            leading: SizedBox(
              width: 44,
              child: CoverArt(palette: s.palette, seed: s.id, imageUrl: s.coverUrl, radius: 4),
            ),
            title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              s.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            onTap: () => Navigator.of(context).pop(s),
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: '搜索歌曲', border: InputBorder.none),
          onChanged: _onChanged,
          onSubmitted: (_) {
            _debounce?.cancel();
            _search();
          },
        ),
      ),
      body: body,
    );
  }
}

/// 动态列表顶部的「分享新鲜事」入口。发出去后调用 [onPosted]（一般是刷新列表）。
class ComposeEventBar extends StatelessWidget {
  const ComposeEventBar({super.key, this.onPosted});

  final VoidCallback? onPosted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: AppColors.cardHover,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () async {
            if (await ComposeEventPage.open(context)) onPosted?.call();
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 20, color: AppColors.textSecondary),
                SizedBox(width: 12),
                Expanded(
                  child: Text('分享新鲜事…', style: TextStyle(color: AppColors.textSecondary)),
                ),
                Icon(Icons.campaign_outlined, size: 20, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
