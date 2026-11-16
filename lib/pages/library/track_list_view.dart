import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/netease_api.dart';
import '../../app/app.dart';
import '../../data/models.dart';
import '../../state/player_controller.dart';
import '../../shell/page_visit.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/song_tile.dart';
import '../../shell/player_bar.dart';

/// 歌曲列表页的通用骨架：头部 + 下拉刷新 + 加载 / 失败 / 空状态 + 歌曲列表。
/// 歌单、专辑、每日推荐、最近播放共用。
class TrackListView extends StatefulWidget {
  const TrackListView({
    super.key,
    this.load,
    this.watch,
    required this.queueTitle,
    required this.header,
    this.reloadKey,
    this.sourceId,
    this.emptyText = '这里还没有歌曲',
    this.trailingFor,
    this.searchable = true,
    this.onRemoveSongs,
  });

  /// 从列表里删歌（自己的歌单、我喜欢）。不为 null 时可以多选批量删除，每行菜单里也能删。
  /// 失败时抛异常。
  final Future<void> Function(List<Song> songs)? onRemoveSongs;

  /// 取歌曲列表。和 [watch] 二选一。
  final Future<List<Song>> Function()? load;

  /// 歌曲列表会先后发来几次（先缓存、再同步后的）。[force] 为 true 表示下拉刷新。
  final Stream<List<Song>> Function(bool force)? watch;

  /// 播放时的队列标题。
  final String queueTitle;

  /// 来源歌单 / 专辑 id，上报最近播放时带上。
  final String? sourceId;

  /// [playAll] 在歌曲加载完之前为 null。
  final Widget Function(BuildContext context, List<Song> tracks, VoidCallback? playAll) header;

  /// 变化时重新加载。
  final Object? reloadKey;
  final String emptyText;

  /// 每行右侧的附加信息（如听歌排行的播放次数）。
  final String? Function(int index)? trailingFor;

  /// 在头部下面显示「搜索列表内歌曲」的输入框。
  final bool searchable;

  @override
  State<TrackListView> createState() => _TrackListViewState();
}

class _TrackListViewState extends State<TrackListView> {
  final _search = TextEditingController();
  String _query = '';

  List<Song>? _tracks;
  Object? _error;

  /// 还在取（有缓存时是在后台同步）。
  bool _loading = true;
  StreamSubscription<List<Song>>? _sub;

  /// 上一次看到的 [PageVisit] 次数。
  int? _visit;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在主框架里被切回来：后台刷新，列表先保留。正在加载时不打断。
    final visit = PageVisit.of(context);
    if (_visit != null && visit != _visit && !_loading) _start(force: true);
    _visit = visit;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TrackListView old) {
    super.didUpdateWidget(old);
    if (old.reloadKey != widget.reloadKey) {
      _tracks = null;
      _start();
    }
  }

  Stream<List<Song>> _source(bool force) =>
      widget.watch?.call(force) ?? Stream.fromFuture(widget.load!());

  /// 开始加载，返回的 Future 在这一轮结束（成功或失败）时完成。
  Future<void> _start({bool force = false}) {
    _sub?.cancel();
    _error = null;
    _loading = true;
    final done = Completer<void>();
    _sub = _source(force).listen(
      (tracks) {
        if (mounted) setState(() => _tracks = tracks);
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          // 已经显示着缓存时不盖掉列表，只提示一下。
          if (_tracks == null) {
            _error = e;
          } else {
            AppScope.toast('刷新失败：${e is ApiException ? e.message : e}');
          }
        });
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (mounted) setState(() => _loading = false);
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    return done.future;
  }

  Future<void> _reload() {
    setState(() {});
    return _start(force: true);
  }

  /// 多选模式下选中的歌 id；为 null 表示不在多选模式。
  Set<String>? _selected;

  void _toggle(String id) => setState(() {
    final sel = _selected!;
    if (!sel.remove(id)) sel.add(id);
  });

  /// 确认后删歌，成功后从列表里去掉。
  Future<void> _remove(List<Song> songs) async {
    final remove = widget.onRemoveSongs;
    if (remove == null || songs.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text('删除歌曲'),
        content: Text(
          songs.length == 1
              ? '确定从歌单中删除「${songs.single.title}」？'
              : '确定从歌单中删除选中的 ${songs.length} 首歌？',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await remove(songs);
    } catch (e) {
      AppScope.toast('删除失败：${e is ApiException ? e.message : e}');
      return;
    }
    if (!mounted) return;
    final ids = {for (final s in songs) s.id};
    setState(() {
      _tracks = [
        for (final t in _tracks ?? const <Song>[])
          if (!ids.contains(t.id)) t,
      ];
      _selected = null;
    });
    AppScope.toast('已删除 ${songs.length} 首');
  }

  /// 多选时多选条固定在顶部，平时跟着列表滚走。
  static Widget _pinIf(bool pinned, Widget child) =>
      pinned ? PinnedHeaderSliver(child: child) : SliverToBoxAdapter(child: child);

  void _play(List<Song> tracks, int i) =>
      PlayerScope.read(context)
          .playQueue(tracks, start: i, title: widget.queueTitle, sourceId: widget.sourceId);

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final tracks = _tracks ?? const <Song>[];
        final loaded = _tracks != null;
        final error = _error;
        // 搜索时只显示匹配的行，序号和点播放仍按完整列表。
        final shown = _query.isEmpty
            ? null
            : [
                for (var i = 0; i < tracks.length; i++)
                  if (songMatches(tracks[i], _query)) i,
              ];
        return RefreshIndicator(
          onRefresh: _reload,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: widget.header(
                  context,
                  tracks,
                  tracks.isEmpty ? null : () => _play(tracks, 0),
                ),
              ),
              if (widget.searchable && loaded && tracks.isNotEmpty)
                SliverToBoxAdapter(
                  child: ListSearchField(
                    controller: _search,
                    hint: '搜索列表内 ${tracks.length} 首歌曲',
                    matched: shown?.length,
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
              if (widget.onRemoveSongs != null && loaded && tracks.isNotEmpty)
                _pinIf(
                  _selected != null,
                  _SelectBar(
                    selected: _selected,
                    total: tracks.length,
                    onStart: () => setState(() => _selected = {}),
                    onCancel: () => setState(() => _selected = null),
                    onAll: () => setState(() {
                      final sel = _selected!;
                      if (sel.length == tracks.length) {
                        sel.clear();
                      } else {
                        sel.addAll(tracks.map((t) => t.id));
                      }
                    }),
                    onRemove: () => _remove([
                      for (final t in tracks)
                        if (_selected!.contains(t.id)) t,
                    ]),
                  ),
                ),
              // 先显示着缓存、后台还在同步：头部下面一条细进度条。
              if (loaded && _loading)
                const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
              if (!loaded && error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorState(error: error, onRetry: _reload),
                )
              else if (!loaded)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (tracks.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      widget.emptyText,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else if (shown != null && shown.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text('没有匹配的歌曲', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: shown?.length ?? tracks.length,
                  itemBuilder: (context, n) {
                    final i = shown?[n] ?? n;
                    final song = tracks[i];
                    final selected = _selected;
                    return SongTile(
                      song: song,
                      index: i + 1,
                      trailing: widget.trailingFor?.call(i),
                      selected: selected?.contains(song.id),
                      onTap: selected == null ? () => _play(tracks, i) : () => _toggle(song.id),
                      onRemove: widget.onRemoveSongs == null ? null : () => _remove([song]),
                    );
                  },
                ),
              SliverToBoxAdapter(child: SizedBox(height: 16 + floatingBarsInset(context))),
            ],
          ),
        );
      },
    );
  }
}

/// 歌曲列表上方的多选条：平时是「批量删除」入口，多选时显示已选数量、全选、删除、完成。
class _SelectBar extends StatelessWidget {
  const _SelectBar({
    required this.selected,
    required this.total,
    required this.onStart,
    required this.onCancel,
    required this.onAll,
    required this.onRemove,
  });

  final Set<String>? selected;
  final int total;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final VoidCallback onAll;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final sel = selected;
    return Container(
      color: sel == null ? null : AppColors.surfaceHigh,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 48,
      child: sel == null
          ? Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.checklist_rounded, size: 20),
                label: const Text('批量删除'),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
              ),
            )
          : Row(
              children: [
                TextButton(onPressed: onAll, child: Text(sel.length == total ? '取消全选' : '全选')),
                Expanded(
                  child: Text(
                    '已选 ${sel.length} 首',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                TextButton(
                  onPressed: sel.isEmpty ? null : onRemove,
                  style: TextButton.styleFrom(foregroundColor: AppColors.negative),
                  child: const Text('删除'),
                ),
                TextButton(onPressed: onCancel, child: const Text('完成')),
              ],
            ),
    );
  }
}

/// 列表上方的搜索框。[matched] 不为 null 时在右侧显示匹配数和清空按钮。
class ListSearchField extends StatelessWidget {
  const ListSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.matched,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final int? matched;

  @override
  Widget build(BuildContext context) {
    final m = matched;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppColors.surfaceHigh,
          hintText: hint,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: m == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$m 个结果',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    IconButton(
                      tooltip: '清空',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
                  ],
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}

/// [query] 按空格分成几个词，每个词都要出现在歌名、别名、歌手或专辑里（不区分大小写）。
bool songMatches(Song song, String query) {
  final text = [song.title, ?song.subtitle, song.artist, song.album].join('\n').toLowerCase();
  return query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every(text.contains);
}

/// 列表页头部：封面、标题、几行说明、「播放全部」和附加按钮。
class CollectionHeader extends StatelessWidget {
  const CollectionHeader({
    super.key,
    required this.title,
    required this.seed,
    this.coverUrl,
    this.fallbackCover,
    this.palette,
    this.icon,
    this.lines = const [],
    this.onPlayAll,
    this.actions = const [],
    this.circular = false,
    this.link,
  });

  final String title;
  final String seed;
  final String? coverUrl;

  /// 封面没有或加载失败时的备用图。
  final Future<String?> Function()? fallbackCover;
  final List<Color>? palette;

  /// 没有封面图时的占位图标。
  final IconData? icon;
  final List<String> lines;
  final VoidCallback? onPlayAll;
  final List<Widget> actions;

  /// 圆形头像（歌手页）。
  final bool circular;

  /// 标题下面一行可以点的文字，例如歌单创建者（点了进用户主页）。
  final ({String text, VoidCallback onTap})? link;

  @override
  Widget build(BuildContext context) {
    final cover = SizedBox(
      width: 112,
      child: ViewableImage(
        url: coverUrl,
        title: title,
        child: CoverArt(
          palette: palette ?? fallbackPalette(seed),
          seed: seed,
          imageUrl: coverUrl,
          fallbackImage: fallbackCover,
          icon: icon,
          radius: circular ? 56 : AppRadius.panel,
          shadow: AppShadows.medium,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          cover,
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (link case final l?) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: l.onTap,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            l.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ],
                for (final l in lines) ...[
                  const SizedBox(height: 4),
                  Text(
                    l,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: onPlayAll,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('播放全部'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.onAccent,
                      ),
                    ),
                    ...actions,
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = error is ApiException ? (error as ApiException).message : '$error';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '加载失败：$text',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
