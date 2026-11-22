import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../shell/player_bar.dart';
import '../../theme/app_theme.dart';
import '../../widgets/playlist_card.dart';
import '../library/track_list_view.dart';
import 'new_songs_page.dart';

/// 发现：三个标签，歌单广场、排行榜、最新音乐。
class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  static const tabs = ['歌单广场', '排行榜', '最新音乐'];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            labelStyle: Theme.of(context).textTheme.titleMedium,
            tabs: [for (final t in tabs) Tab(text: t)],
          ),
          const Expanded(
            child: TabBarView(children: [_PlaylistSquare(), _Toplists(), NewSongsPage()]),
          ),
        ],
      ),
    );
  }
}

/// 歌单广场：选分类，切换「推荐 / 精品」，滑到底自动加载下一页。
class _PlaylistSquare extends StatefulWidget {
  const _PlaylistSquare();

  @override
  State<_PlaylistSquare> createState() => _PlaylistSquareState();
}

class _PlaylistSquareState extends State<_PlaylistSquare> with AutomaticKeepAliveClientMixin {
  static const _all = '全部';
  static const _pageSize = 30;

  String _cat = _all;
  bool _highQuality = false;
  final _items = <Playlist>[];
  bool _more = true;
  bool _loading = false;
  Object? _error;

  /// 精品歌单按时间翻页：上一页最后一个歌单的时间。
  int _before = 0;

  /// 切换分类或类型后，丢掉还在路上的旧请求结果。
  int _generation = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMore();
    });
  }

  void _reset({String? cat, bool? highQuality}) {
    setState(() {
      _cat = cat ?? _cat;
      _highQuality = highQuality ?? _highQuality;
      _items.clear();
      _more = true;
      _before = 0;
      _error = null;
      _loading = false;
      _generation++;
    });
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_more) return;
    final gen = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = AppScope.of(context).api;
    try {
      final List<Playlist> items;
      final bool more;
      if (_highQuality) {
        final r = await api.highQualityPlaylists(cat: _cat, limit: _pageSize, before: _before);
        (items, more) = (r.items, r.more);
        if (gen == _generation) _before = r.lastTime;
      } else {
        final r = await api.playlistSquare(cat: _cat, limit: _pageSize, offset: _items.length);
        (items, more) = (r.items, r.more);
      }
      if (!mounted || gen != _generation) return;
      setState(() {
        final seen = {for (final p in _items) p.id};
        _items.addAll(items.where((p) => seen.add(p.id)));
        _more = more && items.isNotEmpty;
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

  Future<void> _pickCategory() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategorySheet(selected: _cat),
    );
    if (picked != null && picked != _cat) _reset(cat: picked);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = context.scheme;
    final error = _error;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 600) _loadMore();
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () async => _reset(),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    ActionChip(
                      onPressed: _pickCategory,
                      shape: const StadiumBorder(),
                      side: BorderSide.none,
                      backgroundColor: scheme.surfaceContainerHigh,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_cat == _all ? '全部歌单' : _cat),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right_rounded, size: 20),
                        ],
                      ),
                    ),
                    const Spacer(),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: false, label: Text('推荐')),
                        ButtonSegment(value: true, label: Text('精品')),
                      ],
                      selected: {_highQuality},
                      onSelectionChanged: (s) => _reset(highQuality: s.first),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverPlaylistGrid(playlists: _items),
            ),
            SliverPadding(
              padding: EdgeInsets.only(bottom: 24 + floatingBarsInset(context)),
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: error != null
                        ? (_items.isEmpty
                              ? ErrorState(error: error, onRetry: _loadMore)
                              : TextButton(onPressed: _loadMore, child: const Text('加载失败，点击重试')))
                        : _loading
                        ? const CircularProgressIndicator()
                        : _items.isEmpty
                        ? Text('这个分类下没有歌单', style: TextStyle(color: scheme.onSurfaceVariant))
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 歌单分类面板：「全部」加按大类分组的分类，点一个返回分类名。
class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.selected});

  final String selected;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final Future<List<({String group, List<String> names})>> _future = AppScope.of(context).api
      .playlistCategories();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget chips(List<String> names) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final n in names)
          ChoiceChip(
            label: Text(n),
            selected: n == widget.selected,
            onSelected: (_) => Navigator.of(context).pop(n),
          ),
      ],
    );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => FutureBuilder(
        future: _future,
        builder: (context, snap) {
          final groups = snap.data ?? const [];
          return ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Text('歌单分类', style: text.titleLarge),
              const SizedBox(height: 12),
              chips(const [_PlaylistSquareState._all]),
              for (final g in groups) ...[
                const SizedBox(height: 20),
                Text(g.group, style: text.titleSmall),
                const SizedBox(height: 8),
                chips(g.names),
              ],
              if (snap.connectionState != ConnectionState.done)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (snap.hasError)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('分类加载失败')),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 官方排行榜。
class _Toplists extends StatefulWidget {
  const _Toplists();

  @override
  State<_Toplists> createState() => _ToplistsState();
}

class _ToplistsState extends State<_Toplists> with AutomaticKeepAliveClientMixin {
  late Future<List<Playlist>> _future = AppScope.of(context).api.toplists();

  @override
  bool get wantKeepAlive => true;

  Future<void> _reload() async {
    setState(() => _future = AppScope.of(context).api.toplists());
    await _future.catchError((_) => const <Playlist>[]);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<Playlist>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(error: snap.error!, onRetry: _reload);
        final tops = snap.data;
        if (tops == null) return const Center(child: CircularProgressIndicator());
        return RefreshIndicator(
          onRefresh: _reload,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + floatingBarsInset(context)),
                sliver: SliverPlaylistGrid(playlists: tops),
              ),
            ],
          ),
        );
      },
    );
  }
}
