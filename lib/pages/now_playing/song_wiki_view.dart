import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/format.dart';
import '../../data/models.dart';
import '../../state/player_controller.dart';
import '../../widgets/cover_art.dart';
import '../library/playlist_page.dart';

/// 播放页的「百科」：曲风、标签、语种、BPM、获奖等基本信息，相似歌曲，相关歌单。
///
/// 每首歌的百科只取一次，同一首歌来回切换不重新请求。
class SongWikiView extends StatefulWidget {
  const SongWikiView({super.key, required this.song});

  final Song song;

  @override
  State<SongWikiView> createState() => _SongWikiViewState();
}

class _SongWikiViewState extends State<SongWikiView> {
  /// 最近几首歌的百科。失败的不留，下次再取。
  static final _cache = <String, Future<SongWiki>>{};
  static const _cacheSize = 20;

  late Future<SongWiki> _future = _load();

  Future<SongWiki> _load({bool force = false}) {
    final id = widget.song.id;
    if (force) _cache.remove(id);
    final api = AppScope.of(context).api;
    return _cache.putIfAbsent(id, () {
      if (_cache.length >= _cacheSize) _cache.remove(_cache.keys.first);
      return api.songWiki(id).catchError((Object e) {
        _cache.remove(id);
        throw e;
      });
    });
  }

  @override
  void didUpdateWidget(SongWikiView old) {
    super.didUpdateWidget(old);
    if (old.song.id != widget.song.id) _future = _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SongWiki>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return _Message(
            text: '百科加载失败',
            action: TextButton(
              onPressed: () => setState(() => _future = _load(force: true)),
              child: const Text('重试'),
            ),
          );
        }
        final wiki = snap.data;
        if (wiki == null) {
          return const Center(child: CircularProgressIndicator(color: Colors.white70));
        }
        if (wiki.isEmpty) return const _Message(text: '这首歌暂时没有百科');
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          children: [
            if (wiki.facts.isNotEmpty) ...[
              const _SectionTitle('音乐百科'),
              for (final f in wiki.facts) _Fact(label: f.label, values: f.values),
            ],
            if (wiki.similar.isNotEmpty) ...[
              const _SectionTitle('相似歌曲'),
              for (final s in wiki.similar) _SimilarSong(song: s),
            ],
            if (wiki.playlists.isNotEmpty) ...[
              const _SectionTitle('相关歌单'),
              SizedBox(
                height: 168,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: wiki.playlists.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) => _PlaylistTile(playlist: wiki.playlists[i]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(color: Colors.white60)),
          ?action,
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

/// 一条基本信息：左边名称，右边一个或多个值（胶囊）。
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.white60)),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in values)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(v, style: const TextStyle(fontSize: 13, color: Colors.white)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 相似歌曲：点了取歌曲详情，插到当前这首后面并播放。
class _SimilarSong extends StatefulWidget {
  const _SimilarSong({required this.song});

  final SongBrief song;

  @override
  State<_SimilarSong> createState() => _SimilarSongState();
}

class _SimilarSongState extends State<_SimilarSong> {
  bool _busy = false;

  Future<void> _play() async {
    final api = AppScope.of(context).api;
    final player = PlayerScope.read(context);
    setState(() => _busy = true);
    try {
      final songs = await api.songDetails([widget.song.id]);
      final song = songs.firstOrNull;
      if (song == null) {
        AppScope.toast('这首歌暂时放不了');
        return;
      }
      await player.playNext(song);
      await player.next();
    } catch (e) {
      AppScope.toast('播放失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.song;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox.square(
        dimension: 44,
        child: CoverArt(
          palette: fallbackPalette(s.id),
          seed: s.id,
          imageUrl: s.coverUrl,
          radius: 6,
        ),
      ),
      title: Text(
        s.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white),
      ),
      subtitle: Text(
        s.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white60),
      ),
      trailing: _busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
            )
          : const Icon(Icons.play_circle_outline_rounded, color: Colors.white70),
      onTap: _busy ? null : _play,
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final p = playlist;
    return GestureDetector(
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => PlaylistPage(playlist: p))),
      child: SizedBox(
        width: 112,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox.square(
                  dimension: 112,
                  child: CoverArt(palette: p.palette, seed: p.id, imageUrl: p.coverUrl, radius: 10),
                ),
                if (p.playCount > 0)
                  Positioned(
                    right: 6,
                    top: 4,
                    child: Text(
                      '▶ ${formatPlayCount(p.playCount)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        shadows: [Shadow(blurRadius: 4)],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              p.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}
