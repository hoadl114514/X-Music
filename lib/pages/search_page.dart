import 'dart:async';

import 'package:flutter/material.dart';

import '../api/netease_api.dart';
import '../app/app.dart';
import '../data/models.dart';
import '../shell/player_bar.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_art.dart';
import '../widgets/image_viewer.dart';
import '../widgets/playlist_card.dart';
import '../widgets/song_tile.dart';
import 'library/playlist_page.dart';
import 'music/artist_page.dart';
import 'music/nav.dart';

/// 搜索。输入时显示联想（匹配的搜索历史 + 补全词 + 几条快速结果，像搜索引擎的下拉框），
/// 输入框为空时显示搜索历史和热搜；
/// 提交后显示单曲 / 歌单 / 歌手 / 专辑四个标签，各自滚到底自动加载下一页。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.keyword = '', this.embedded = false});

  /// 为空时进入输入状态。
  final String keyword;

  /// 作为底栏的「搜索」标签显示：没有返回键，不自动弹键盘，底栏由主框架提供。
  final bool embedded;

  /// 直接搜索 [keyword]。
  static Future<void> open(BuildContext context, String keyword) {
    final k = keyword.trim();
    if (k.isEmpty) return Future.value();
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => SearchPage(keyword: k)));
  }

  /// 打开搜索页，光标在输入框里。
  static Future<void> start(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchPage()));

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final _input = TextEditingController(text: widget.keyword);
  final _focus = FocusNode();
  late String _keyword = widget.keyword.trim();

  /// true 显示搜索结果，false 显示联想 / 热搜。
  late bool _showResults = _keyword.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_keyword.isNotEmpty) AppScope.of(context).settings.addSearchHistory(_keyword);
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _search(String keyword) {
    final k = keyword.trim();
    if (k.isEmpty) return;
    _input.value = TextEditingValue(
      text: k,
      selection: TextSelection.collapsed(offset: k.length),
    );
    _focus.unfocus();
    AppScope.of(context).settings.addSearchHistory(k);
    setState(() {
      _keyword = k;
      _showResults = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        titleSpacing: widget.embedded ? 16 : 0,
        title: TextField(
          controller: _input,
          focusNode: _focus,
          autofocus: !_showResults && !widget.embedded,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          // 一改输入就回到联想状态。
          onChanged: (_) {
            if (_showResults) setState(() => _showResults = false);
          },
          onTap: () {
            if (_showResults && _input.text.trim() != _keyword) {
              setState(() => _showResults = false);
            }
          },
          decoration: InputDecoration(
            hintText: '搜索音乐、歌手',
            border: InputBorder.none,
            suffixIcon: ListenableBuilder(
              listenable: _input,
              builder: (context, _) => _input.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: '清空',
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () {
                        _input.clear();
                        _focus.requestFocus();
                        setState(() => _showResults = false);
                      },
                    ),
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _search(_input.text),
            tooltip: '搜索',
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ),
      body: _showResults
          ? _Results(key: ValueKey(_keyword), keyword: _keyword)
          : _Suggestions(input: _input, onSearch: _search),
      extendBody: !widget.embedded,
      bottomNavigationBar: widget.embedded ? null : const FloatingBottomBar(),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({super.key, required this.keyword});

  final String keyword;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    final k = keyword;
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: '单曲'),
              Tab(text: '歌单'),
              Tab(text: '歌手'),
              Tab(text: '专辑'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _PagedResults<Song>(
                  key: ValueKey('song:$k'),
                  noun: '歌曲',
                  fetch: (offset) async {
                    final r = await api.searchSongs(k, limit: _pageSize, offset: offset);
                    return (items: r.songs, total: r.total);
                  },
                  itemBuilder: (context, items, i) => SongTile(
                    song: items[i],
                    onTap: () =>
                        PlayerScope.read(context)
                            .playQueue(List.of(items), start: i, title: '搜索：$k'),
                  ),
                ),
                _PagedResults<Playlist>(
                  key: ValueKey('playlist:$k'),
                  noun: '歌单',
                  fetch: (offset) => api.searchPlaylists(k, limit: _pageSize, offset: offset),
                  itemBuilder: (context, items, i) => PlaylistTile(playlist: items[i]),
                ),
                _PagedResults<Artist>(
                  key: ValueKey('artist:$k'),
                  noun: '歌手',
                  fetch: (offset) => api.searchArtists(k, limit: _pageSize, offset: offset),
                  itemBuilder: (context, items, i) => _ArtistTile(artist: items[i]),
                ),
                _PagedResults<Album>(
                  key: ValueKey('album:$k'),
                  noun: '专辑',
                  fetch: (offset) => api.searchAlbums(k, limit: _pageSize, offset: offset),
                  itemBuilder: (context, items, i) => AlbumTile(album: items[i]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 输入状态：空输入显示热搜；有输入时防抖 250ms 后取联想词和快速结果。
class _Suggestions extends StatefulWidget {
  const _Suggestions({required this.input, required this.onSearch});

  final TextEditingController input;
  final ValueChanged<String> onSearch;

  @override
  State<_Suggestions> createState() => _SuggestionsState();
}

class _SuggestionsState extends State<_Suggestions> {
  static const _debounce = Duration(milliseconds: 250);

  Timer? _timer;
  String _text = '';
  List<String> _hot = const [];
  List<String> _keywords = const [];
  SearchSuggestion _quick = const SearchSuggestion();

  /// 只认最新一次输入的结果。
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.input.addListener(_onInput);
    _loadHot();
    _onInput();
  }

  @override
  void dispose() {
    widget.input.removeListener(_onInput);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadHot() async {
    try {
      final hot = await AppScope.of(context).api.hotSearches();
      if (mounted) setState(() => _hot = hot);
    } catch (_) {
      // 热搜取不到就不显示。
    }
  }

  void _onInput() {
    final text = widget.input.text.trim();
    if (text == _text) return;
    _text = text;
    _timer?.cancel();
    final gen = ++_generation;
    if (text.isEmpty) {
      setState(() {
        _keywords = const [];
        _quick = const SearchSuggestion();
      });
      return;
    }
    _timer = Timer(_debounce, () => _fetch(text, gen));
  }

  Future<void> _fetch(String text, int gen) async {
    final api = AppScope.of(context).api;
    // 两个接口互不影响，一个失败另一个照常显示。
    final keywords = api.searchKeywords(text).catchError((Object _) => <String>[]);
    final quick = api.searchSuggest(text).catchError((Object _) => const SearchSuggestion());
    final (k, q) = (await keywords, await quick);
    if (!mounted || gen != _generation) return;
    setState(() {
      _keywords = k;
      _quick = q;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_text.isEmpty) return _hotList(context);
    final q = _quick;
    // 输入本身也作为第一条，方便直接搜。
    final words = [_text, ..._keywords.where((k) => k != _text)];
    final lower = _text.toLowerCase();
    final history = AppScope.of(context).settings.searchHistory
        .where((h) => h != _text && h.toLowerCase().contains(lower))
        .take(3);
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        for (final h in history)
          ListTile(
            dense: true,
            leading: Icon(Icons.history_rounded, size: 20, color: context.colors.textMuted),
            title: Text(h, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => widget.onSearch(h),
          ),
        for (final w in words.take(8))
          ListTile(
            dense: true,
            leading: Icon(Icons.search_rounded, size: 20, color: context.colors.textMuted),
            title: Text(w, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: '填入',
              icon: Icon(Icons.north_west_rounded, size: 18, color: context.colors.textMuted),
              onPressed: () {
                widget.input.value = TextEditingValue(
                  text: w,
                  selection: TextSelection.collapsed(offset: w.length),
                );
              },
            ),
            onTap: () => widget.onSearch(w),
          ),
        if (q.artists.isNotEmpty || q.songs.isNotEmpty || q.albums.isNotEmpty) ...[
          const Divider(),
          for (final a in q.artists.take(2))
            ListTile(
              leading: _thumb(
                seed: a.id,
                url: a.avatarUrl,
                title: a.name,
                icon: Icons.person_rounded,
                round: true,
              ),
              title: Text(a.name),
              subtitle: const Text('歌手'),
              onTap: () => openArtist(context, ArtistRef(a.id, a.name)),
            ),
          for (final (i, s) in q.songs.take(4).indexed)
            ListTile(
              leading: _thumb(
                seed: s.id,
                url: s.coverUrl,
                title: s.title,
                icon: Icons.music_note_rounded,
              ),
              title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('单曲 · ${s.artist}', maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () =>
                  PlayerScope.read(context)
                      .playQueue(q.songs.take(4).toList(), start: i, title: '搜索：$_text'),
            ),
          for (final a in q.albums.take(2))
            ListTile(
              leading: _thumb(
                seed: a.id,
                url: a.coverUrl,
                title: a.name,
                icon: Icons.album_rounded,
              ),
              title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('专辑 · ${a.artist}', maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => openAlbum(context, a.id, name: a.name),
            ),
          for (final p in q.playlists.take(2))
            ListTile(
              leading: _thumb(
                seed: p.id,
                url: p.coverUrl,
                title: p.name,
                icon: Icons.queue_music_rounded,
              ),
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: const Text('歌单'),
              onTap: () => SubPage.push(context, PlaylistPage(playlist: p)),
            ),
        ],
      ],
    );
  }

  /// 联想结果左侧的小图：歌手圆形头像，其他方形封面。长按看大图。
  Widget _thumb({
    required String seed,
    required String? url,
    required String title,
    required IconData icon,
    bool round = false,
  }) => SizedBox(
    width: 44,
    child: ViewableImage(
      url: url,
      title: title,
      child: CoverArt(
        palette: fallbackPalette(seed),
        seed: seed,
        imageUrl: url,
        radius: round ? 22 : 6,
        icon: url == null ? icon : null,
      ),
    ),
  );

  Widget _hotList(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final history = settings.searchHistory;
        return ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + floatingBarsInset(context)),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if (history.isNotEmpty) ...[
              Row(
                children: [
                  Text('搜索历史', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: '清空搜索历史',
                    icon: Icon(Icons.delete_outline_rounded, color: context.colors.textMuted),
                    onPressed: () => _confirmClear(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final w in history)
                    InputChip(
                      label: Text(w),
                      onPressed: () => widget.onSearch(w),
                      onDeleted: () => settings.removeSearchHistory(w),
                      deleteButtonTooltipMessage: '删除',
                      deleteIcon: const Icon(Icons.close_rounded, size: 16),
                    ),
                ],
              ),
              const SizedBox(height: 24),
            ],
            if (_hot.isNotEmpty) ...[
              Text('热搜', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (i, w) in _hot.indexed)
                    ActionChip(
                      avatar: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: i < 3 ? context.colors.accent : context.colors.textMuted,
                        ),
                      ),
                      label: Text(w),
                      onPressed: () => widget.onSearch(w),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text('清空全部搜索历史？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('清空')),
        ],
      ),
    );
    if (ok == true && context.mounted) AppScope.of(context).settings.clearSearchHistory();
  }
}

const _pageSize = 30;

/// 分页结果列表：首次进入加载第一页，滚到底加载下一页。
class _PagedResults<T> extends StatefulWidget {
  const _PagedResults({
    super.key,
    required this.noun,
    required this.fetch,
    required this.itemBuilder,
  });

  final String noun;
  final Future<({List<T> items, int total})> Function(int offset) fetch;
  final Widget Function(BuildContext context, List<T> items, int index) itemBuilder;

  @override
  State<_PagedResults<T>> createState() => _PagedResultsState<T>();
}

class _PagedResultsState<T> extends State<_PagedResults<T>> with AutomaticKeepAliveClientMixin {
  final List<T> _items = [];
  int _total = 0;
  bool _loading = false;
  bool _started = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  bool get _hasMore => !_started || _items.length < _total;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final r = await widget.fetch(_items.length);
      if (!mounted) return;
      setState(() {
        _started = true;
        _items.addAll(r.items);
        // 服务端偶尔少给一页，以实际拿到的为准，避免无限加载。
        _total = r.items.isEmpty ? _items.length : r.total;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 400 && _hasMore && !_loading && _error == null) _loadMore();
        return false;
      },
      child: ListView.builder(
        itemCount: _items.length + 1,
        itemBuilder: (context, i) {
          if (i < _items.length) return widget.itemBuilder(context, _items, i);
          return _Footer(
            loading: _loading,
            error: _error,
            empty: _started && _items.isEmpty,
            done: !_hasMore,
            noun: widget.noun,
            onRetry: _loadMore,
          );
        },
      ),
    );
  }
}

class _ArtistTile extends StatelessWidget {
  const _ArtistTile({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    final a = artist;
    return ListTile(
      leading: SizedBox(
        width: 52,
        child: ViewableImage(
          url: a.avatarUrl,
          title: a.name,
          child: CoverArt(
            palette: fallbackPalette(a.id),
            seed: a.id,
            imageUrl: a.avatarUrl,
            radius: 26,
            icon: Icons.person_rounded,
          ),
        ),
      ),
      title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '单曲 ${a.songCount} · 专辑 ${a.albumCount}',
        style: TextStyle(color: context.colors.textSecondary),
      ),
      onTap: () => openArtist(context, ArtistRef(a.id, a.name)),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.loading,
    required this.error,
    required this.empty,
    required this.done,
    required this.noun,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final bool empty;
  final bool done;
  final String noun;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: context.colors.textMuted);
    final Widget child;
    if (loading) {
      child = const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (error != null) {
      child = TextButton(onPressed: onRetry, child: Text('$error，点击重试'));
    } else if (empty) {
      child = Text('没有找到相关$noun', style: style);
    } else if (done) {
      child = Text('没有更多了', style: style);
    } else {
      child = const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: child),
    );
  }
}
