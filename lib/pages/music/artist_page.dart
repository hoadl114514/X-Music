import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/image_viewer.dart';
import '../library/track_list_view.dart';
import 'nav.dart';

/// 歌手的全部歌曲（用户主页的标签），可按热度或发行时间排序。
class ArtistAllSongs extends StatefulWidget {
  const ArtistAllSongs({super.key, required this.artist});

  final ArtistRef artist;

  @override
  State<ArtistAllSongs> createState() => _ArtistAllSongsState();
}

class _ArtistAllSongsState extends State<ArtistAllSongs> with AutomaticKeepAliveClientMixin {
  /// true 按发行时间从新到旧，false 按热度。
  bool _byTime = true;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final byTime = _byTime;
    return TrackListView(
      reloadKey: byTime,
      load: () => AppScope.of(context).api.artistAllSongs(widget.artist.id, byTime: byTime),
      queueTitle: '${widget.artist.name} 全部歌曲',
      emptyText: '没有歌曲',
      header: (context, tracks, playAll) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            FilledButton.icon(
              onPressed: playAll,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('播放全部'),
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.accent,
                foregroundColor: context.colors.onAccent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tracks.isEmpty ? '' : '共 ${tracks.length} 首',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
              ),
            ),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(value: false, label: Text('热度')),
                ButtonSegment(value: true, label: Text('最新')),
              ],
              selected: {byTime},
              onSelectionChanged: (v) => setState(() => _byTime = v.first),
            ),
          ],
        ),
      ),
    );
  }
}

/// 歌手的专辑（用户主页的标签），可搜索。
class ArtistAlbums extends StatefulWidget {
  const ArtistAlbums({super.key, required this.artist});

  final ArtistRef artist;

  @override
  State<ArtistAlbums> createState() => _ArtistAlbumsState();
}

class _ArtistAlbumsState extends State<ArtistAlbums> with AutomaticKeepAliveClientMixin {
  static const _pageSize = 30;

  final List<Album> _albums = [];
  bool _more = true;
  bool _loading = false;
  Object? _error;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 搜索时把剩下的专辑都取完（[_loadMore] 会一页接一页取），否则只能搜到已加载的。
  void _onQuery(String v) {
    setState(() => _query = v.trim());
    if (_query.isNotEmpty) unawaited(_loadMore());
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_more) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await AppScope.of(context).api
          .artistAlbums(widget.artist.id, limit: _pageSize, offset: _albums.length);
      if (!mounted) return;
      setState(() {
        _albums.addAll(r.albums);
        _more = r.more && r.albums.isNotEmpty;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (mounted && _query.isNotEmpty && _more && _error == null) unawaited(_loadMore());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_albums.isEmpty && _error != null) {
      return ErrorState(error: _error!, onRetry: _loadMore);
    }
    if (_albums.isEmpty && _loading) return const Center(child: CircularProgressIndicator());
    if (_albums.isEmpty) {
      return Center(
        child: Text('没有专辑', style: TextStyle(color: context.colors.textSecondary)),
      );
    }
    final shown = _query.isEmpty
        ? _albums
        : [
            for (final a in _albums)
              if (albumMatches(a, _query)) a,
          ];
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 400) _loadMore();
        return false;
      },
      child: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: shown.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) {
            return ListSearchField(
              controller: _search,
              hint: _more ? '搜索专辑' : '搜索 ${_albums.length} 张专辑',
              matched: _query.isEmpty ? null : shown.length,
              onChanged: _onQuery,
            );
          }
          if (i == shown.length + 1) {
            if (_more) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (_query.isNotEmpty && shown.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text('没有匹配的专辑', style: TextStyle(color: context.colors.textSecondary)),
                ),
              );
            }
            return const SizedBox(height: 16);
          }
          return AlbumTile(album: shown[i - 1]);
        },
      ),
    );
  }
}

/// 专辑名、歌手或发行年份包含 [query] 的每个词（不区分大小写）。
bool albumMatches(Album a, String query) {
  final text = [
    a.name,
    a.artist,
    if (a.publishTime case final t?) '${t.year}',
  ].join('\n').toLowerCase();
  return query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every(text.contains);
}

/// 歌手简介：默认显示三行，点「展开」显示完整简介和分段的详细介绍（展开时才去取）。
class ArtistIntro extends StatefulWidget {
  const ArtistIntro({super.key, required this.artistId, required this.brief});

  final String artistId;
  final String brief;

  @override
  State<ArtistIntro> createState() => _ArtistIntroState();
}

class _ArtistIntroState extends State<ArtistIntro> {
  bool _expanded = false;
  Future<List<({String title, String text})>>? _details;

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _details ??= AppScope.of(context).api
            .artistIntroduction(widget.artistId)
            .catchError((Object _) => <({String title, String text})>[]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = TextStyle(fontSize: 13, height: 1.6, color: context.colors.textSecondary);
    return InkWell(
      onTap: _toggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.brief,
                maxLines: _expanded ? null : 3,
                overflow: _expanded ? null : TextOverflow.ellipsis,
                style: body,
              ),
              if (_expanded)
                FutureBuilder(
                  future: _details,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final d in snap.data ?? const <({String title, String text})>[]) ...[
                          const SizedBox(height: 12),
                          if (d.title.isNotEmpty)
                            Text(
                              d.title,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                          const SizedBox(height: 4),
                          Text(d.text, style: body),
                        ],
                      ],
                    );
                  },
                ),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded ? '收起' : '展开',
                      style: TextStyle(fontSize: 12, color: context.colors.textMuted),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 18,
                      color: context.colors.textMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 专辑列表的一行。
class AlbumTile extends StatelessWidget {
  const AlbumTile({super.key, required this.album});

  final Album album;

  @override
  Widget build(BuildContext context) {
    final a = album;
    return ListTile(
      leading: SizedBox(
        width: 52,
        child: ViewableImage(
          url: a.coverUrl,
          title: a.name,
          child: CoverArt(
            palette: fallbackPalette(a.id),
            seed: a.id,
            imageUrl: a.coverUrl,
            radius: 6,
          ),
        ),
      ),
      title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (a.artist.isNotEmpty) a.artist,
          if (a.publishTime case final t?) '${t.year}',
          if (a.size > 0) '${a.size} 首',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.colors.textSecondary),
      ),
      onTap: () => openAlbum(context, a.id, name: a.name),
    );
  }
}
