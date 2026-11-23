import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/format.dart';
import '../../data/models.dart';
import '../../state/player_controller.dart';
import '../../widgets/cover_art.dart';
import '../library/playlist_page.dart';
import '../music/nav.dart';
import '../social/social_widgets.dart';

/// 播放页的「百科」：曲风、标签、语种、BPM、获奖等基本信息，相似歌曲，关于艺人，相关歌单。
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
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          children: [
            if (wiki.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: _Message(text: '这首歌暂时没有百科'),
              ),
            if (wiki.facts.isNotEmpty) ...[
              const _SectionTitle('音乐百科'),
              for (final f in wiki.facts) _Fact(label: f.label, values: f.values),
            ],
            if (wiki.similar.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SimilarCard(songs: wiki.similar),
            ],
            _ArtistSection(song: widget.song),
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

/// 卡片底色：深色播放页上的一层半透明白。
const _cardColor = Color(0x14FFFFFF);

/// 把百科里的歌曲简介换成能播放的歌曲（按传入顺序，取不到的跳过）。
Future<List<Song>> _resolve(BuildContext context, List<SongBrief> briefs) async {
  final songs = await AppScope.of(context).api.songDetails([for (final b in briefs) b.id]);
  final byId = {for (final s in songs) s.id: s};
  return [for (final b in briefs) ?byId[b.id]];
}

/// 「喜欢这首歌的人也爱听」：先显示三首，展开看全部；可以插播一首或全部插播。
/// 点一行直接播放这首。
class _SimilarCard extends StatefulWidget {
  const _SimilarCard({required this.songs});

  final List<SongBrief> songs;

  @override
  State<_SimilarCard> createState() => _SimilarCardState();
}

class _SimilarCardState extends State<_SimilarCard> {
  static const _folded = 3;

  bool _expanded = false;

  /// 正在处理的歌 id；插播全部时为空串。
  String? _busy;

  Future<void> _run(String key, List<SongBrief> briefs, {required bool play}) async {
    final player = PlayerScope.read(context);
    setState(() => _busy = key);
    try {
      final songs = await _resolve(context, briefs);
      if (songs.isEmpty) {
        AppScope.toast('这首歌暂时放不了');
        return;
      }
      // 倒着插到当前歌后面，插完顺序和列表一致。
      for (final s in songs.reversed) {
        await player.playNext(s);
      }
      if (play) {
        await player.next();
      } else {
        AppScope.toast(songs.length == 1 ? '已插播' : '已插播 ${songs.length} 首');
      }
    } catch (e) {
      AppScope.toast('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.songs;
    final shown = _expanded ? all : all.take(_folded).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '喜欢这首歌的人也爱听',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
              TextButton.icon(
                onPressed: _busy != null ? null : () => _run('', all, play: false),
                icon: _busy == ''
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                      )
                    : const Icon(Icons.playlist_add_rounded, size: 20),
                label: const Text('插播全部'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  shape: const StadiumBorder(),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final (i, s) in shown.indexed)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _busy != null ? null : () => _run(s.id, [s], play: true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(fontSize: 16, color: Colors.white54),
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: s.title,
                          style: const TextStyle(fontSize: 15, color: Colors.white),
                          children: [
                            if (s.artist.isNotEmpty)
                              TextSpan(
                                text: ' - ${s.artist}',
                                style: const TextStyle(fontSize: 12, color: Colors.white54),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _busy == s.id
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white70,
                              ),
                            ),
                          )
                        : IconButton(
                            tooltip: '插播',
                            onPressed: _busy != null ? null : () => _run(s.id, [s], play: false),
                            icon: const Icon(Icons.playlist_add_rounded, color: Colors.white60),
                          ),
                  ],
                ),
              ),
            ),
          if (all.length > _folded)
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                iconAlignment: IconAlignment.end,
                icon: Icon(
                  _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                ),
                label: Text(_expanded ? '收起' : '全部 ${all.length}'),
                style: TextButton.styleFrom(foregroundColor: Colors.white54),
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 「关于艺人」：这首歌的前两位歌手各一张卡片；歌手更多时底下加「全部艺人」。
class _ArtistSection extends StatelessWidget {
  const _ArtistSection({required this.song});

  final Song song;

  static const _cards = 2;

  @override
  Widget build(BuildContext context) {
    final artists = [
      for (final a in song.artists)
        if (a.id.isNotEmpty && a.id != '0') a,
    ];
    if (artists.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in artists.take(_cards)) _ArtistCard(key: ValueKey(a.id), artist: a),
        if (artists.length > _cards)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _AllArtistsRow(artists: artists),
          ),
      ],
    );
  }
}

class _ArtistCard extends StatefulWidget {
  const _ArtistCard({super.key, required this.artist});

  final ArtistRef artist;

  @override
  State<_ArtistCard> createState() => _ArtistCardState();
}

class _ArtistCardState extends State<_ArtistCard> {
  /// 最近看过的歌手资料。失败的不留，下次再取。
  static final _cache = <String, Future<ArtistProfile>>{};
  static const _cacheSize = 30;

  late final Future<ArtistProfile> _future = _load();

  Future<ArtistProfile> _load() {
    final id = widget.artist.id;
    final api = AppScope.of(context).api;
    return _cache.putIfAbsent(id, () {
      if (_cache.length >= _cacheSize) _cache.remove(_cache.keys.first);
      return api.artistProfile(id).catchError((Object e) {
        _cache.remove(id);
        throw e;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ArtistProfile>(
      future: _future,
      builder: (context, snap) {
        final p = snap.data;
        // 取不到资料就不占位置。
        if (p == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _ArtistCardBody(ref: widget.artist, profile: p),
        );
      },
    );
  }
}

class _ArtistCardBody extends StatelessWidget {
  const _ArtistCardBody({required this.ref, required this.profile});

  final ArtistRef ref;
  final ArtistProfile profile;

  @override
  Widget build(BuildContext context) {
    final a = profile.artist;
    final fans = profile.fans;
    final album = profile.latestAlbum;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => openArtist(context, ref),
            child: AspectRatio(
              aspectRatio: 1.15,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CoverArt(
                    palette: fallbackPalette(a.id),
                    seed: a.id,
                    imageUrl: profile.coverUrl ?? a.avatarUrl,
                    radius: 0,
                    icon: Icons.person_rounded,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x55000000), Color(0x00000000), Color(0xCC000000)],
                        stops: [0, 0.35, 1],
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 16,
                    top: 14,
                    child: Text(
                      '关于艺人',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                a.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            FollowButton(
                              artistId: a.id,
                              followed: profile.followed,
                              compact: true,
                              translucent: true,
                            ),
                          ],
                        ),
                        if (fans != null && fans > 0)
                          Text(
                            '${formatPlayCount(fans)}粉丝',
                            style: const TextStyle(fontSize: 13, color: Colors.white70),
                          ),
                        if (a.description case final desc?) ...[
                          const SizedBox(height: 6),
                          Text(
                            desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (album != null) _LatestAlbumRow(album: album),
        ],
      ),
    );
  }
}

/// 歌手卡片底部的最新专辑：三个月内发行的标「新专辑」。
class _LatestAlbumRow extends StatelessWidget {
  const _LatestAlbumRow({required this.album});

  final Album album;

  static const _newWithin = Duration(days: 90);

  @override
  Widget build(BuildContext context) {
    final time = album.publishTime;
    final isNew = time != null && DateTime.now().difference(time) < _newWithin;
    String two(int n) => n.toString().padLeft(2, '0');
    final date = time == null ? null : '${time.year}-${two(time.month)}-${two(time.day)}发行';
    void open() => openAlbum(context, album.id, name: album.name);
    return InkWell(
      onTap: open,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 52,
              child: CoverArt(
                palette: fallbackPalette(album.id),
                seed: album.id,
                imageUrl: album.coverUrl,
                radius: 6,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          isNew ? '新专辑' : '最新专辑',
                          style: const TextStyle(fontSize: 10, color: Colors.white70),
                        ),
                      ),
                      if (date != null) ...[
                        const SizedBox(width: 6),
                        Text(date, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: open,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                shape: const StadiumBorder(),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('查看'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「全部艺人 · 共 N 名」：点了选一位歌手进主页。
class _AllArtistsRow extends StatelessWidget {
  const _AllArtistsRow({required this.artists});

  final List<ArtistRef> artists;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    final faces = artists.take(3).toList();
    const size = 26.0;
    return Material(
      color: _cardColor,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final picked = await showModalBottomSheet<ArtistRef>(
            context: context,
            showDragHandle: true,
            builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '全部艺人',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  for (final a in artists)
                    ListTile(
                      leading: SizedBox(
                        width: 40,
                        child: CoverArt(
                          palette: fallbackPalette(a.id),
                          seed: a.id,
                          radius: 20,
                          icon: Icons.person_rounded,
                          fallbackImage: () => api.artistAvatar(a.id),
                        ),
                      ),
                      title: Text(a.name),
                      onTap: () => Navigator.of(context).pop(a),
                    ),
                ],
              ),
            ),
          );
          if (picked != null && context.mounted) await openArtist(context, picked);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '全部艺人',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
              SizedBox(
                width: size + (faces.length - 1) * size * 0.6,
                height: size,
                child: Stack(
                  children: [
                    for (final (i, a) in faces.indexed)
                      Positioned(
                        left: i * size * 0.6,
                        child: SizedBox.square(
                          dimension: size,
                          child: CoverArt(
                            palette: fallbackPalette(a.id),
                            seed: a.id,
                            radius: size / 2,
                            icon: Icons.person_rounded,
                            fallbackImage: () => api.artistAvatar(a.id),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '共${artists.length}名',
                style: const TextStyle(fontSize: 13, color: Colors.white54),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
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
