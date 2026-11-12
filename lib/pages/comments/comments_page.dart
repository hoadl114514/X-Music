import 'package:flutter/material.dart';

import '../../api/netease_api.dart';
import '../../app/app.dart';
import '../../data/format.dart';
import '../../data/models.dart';
import '../../state/account_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/copy_sheet.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/image_viewer.dart';
import '../login_page.dart';
import '../music/nav.dart';

/// 评论区：「热门」「最新」两个标签，各自滚到底加载下一页；点评论回复，「N 条回复」展开楼中楼；
/// 长按复制 / 回复 / 删除自己的评论；底部输入框发评论。歌曲、歌单、专辑共用。
class CommentsPage extends StatefulWidget {
  const CommentsPage({
    super.key,
    required this.target,
    required this.id,
    required this.title,
    this.subtitle,
    this.coverUrl,
  });

  final CommentTarget target;
  final String id;

  /// 顶部显示的资源名和副标题（歌手、创建者）。
  final String title;
  final String? subtitle;
  final String? coverUrl;

  static Future<void> open(
    BuildContext context, {
    required CommentTarget target,
    required String id,
    required String title,
    String? subtitle,
    String? coverUrl,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CommentsPage(
        target: target,
        id: id,
        title: title,
        subtitle: subtitle,
        coverUrl: coverUrl,
      ),
    ),
  );

  static Future<void> openSong(BuildContext context, Song song) => open(
    context,
    target: CommentTarget.song,
    id: song.id,
    title: song.title,
    subtitle: song.artist,
    coverUrl: song.coverUrl,
  );

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> with SingleTickerProviderStateMixin {
  late final String _threadId = widget.target.threadId(widget.id);
  final _latestKey = GlobalKey<_CommentListState>();
  final _composerKey = GlobalKey<_ComposerState>();
  late final _tabs = TabController(length: CommentSort.values.length, vsync: this);
  int? _total;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(_total == null ? '评论' : '评论（${formatPlayCount(_total!)}）'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [for (final s in CommentSort.values) Tab(text: s.label)],
        ),
      ),
      body: Column(
        children: [
          _ResourceHeader(
            seed: _threadId,
            title: widget.title,
            subtitle: widget.subtitle,
            coverUrl: widget.coverUrl,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final s in CommentSort.values)
                  _CommentList(
                    key: s == CommentSort.latest ? _latestKey : null,
                    threadId: _threadId,
                    sort: s,
                    onTotal: (t) {
                      if (_total != t) setState(() => _total = t);
                    },
                    onReply: (c) => _composerKey.currentState?.replyTo(c),
                  ),
              ],
            ),
          ),
          _Composer(
            key: _composerKey,
            threadId: _threadId,
            onSent: (c, replyTo) {
              if (c != null && replyTo == null) _latestKey.currentState?.prepend(c);
              if (replyTo == null) _tabs.animateTo(CommentSort.latest.index);
            },
          ),
        ],
      ),
    );
  }
}

class _ResourceHeader extends StatelessWidget {
  const _ResourceHeader({
    required this.seed,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
  });

  final String seed;
  final String title;
  final String? subtitle;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: ViewableImage(
              url: coverUrl,
              title: title,
              child: CoverArt(
                palette: fallbackPalette(seed),
                seed: seed,
                imageUrl: coverUrl,
                radius: 6,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onLongPress: () => copyText(title, label: '名称'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  if (subtitle case final s? when s.isNotEmpty)
                    Text(
                      s,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 列表

class _CommentList extends StatefulWidget {
  const _CommentList({
    super.key,
    required this.threadId,
    required this.sort,
    required this.onTotal,
    required this.onReply,
  });

  final String threadId;
  final CommentSort sort;
  final ValueChanged<int> onTotal;
  final ValueChanged<Comment> onReply;

  @override
  State<_CommentList> createState() => _CommentListState();
}

class _CommentListState extends State<_CommentList> with AutomaticKeepAliveClientMixin {
  static const _pageSize = 20;

  final List<Comment> _items = [];
  final Set<int> _seen = {};
  String? _cursor;
  int _pageNo = 1;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  /// 刚发出去的评论放到最前面。
  void prepend(Comment c) {
    if (!_seen.add(c.id)) return;
    setState(() => _items.insert(0, c));
  }

  Future<void> _refresh() async {
    setState(() {
      _items.clear();
      _seen.clear();
      _cursor = null;
      _pageNo = 1;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await AppScope.of(context).api.comments(
        widget.threadId,
        sort: widget.sort,
        pageNo: _pageNo,
        pageSize: _pageSize,
        cursor: _cursor,
      );
      if (!mounted) return;
      setState(() {
        // 翻页时接口偶尔会重复给出上一页末尾的评论。
        _items.addAll(page.comments.where((c) => _seen.add(c.id)));
        _cursor = page.cursor;
        _pageNo++;
        _hasMore = page.hasMore && page.comments.isNotEmpty;
        _error = null;
      });
      if (page.total > 0) widget.onTotal(page.total);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _replace(Comment c) {
    final i = _items.indexWhere((e) => e.id == c.id);
    if (i >= 0) setState(() => _items[i] = c);
  }

  void _remove(Comment c) => setState(() => _items.removeWhere((e) => e.id == c.id));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600 && _hasMore && !_loading && _error == null) {
            _loadMore();
          }
          return false;
        },
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _items.length + 1,
          separatorBuilder: (_, i) => i < _items.length - 1
              ? const Divider(height: 1, indent: 64, color: AppColors.border)
              : const SizedBox.shrink(),
          itemBuilder: (context, i) {
            if (i == _items.length) {
              return _ListFooter(
                loading: _loading,
                error: _error,
                empty: !_hasMore && _items.isEmpty,
                done: !_hasMore,
                onRetry: _loadMore,
              );
            }
            final c = _items[i];
            return CommentTile(
              comment: c,
              threadId: widget.threadId,
              onChanged: _replace,
              onDeleted: _remove,
              onReply: () => widget.onReply(c),
              onOpenReplies: c.replyCount > 0
                  ? () => showFloorSheet(context, widget.threadId, c, onChanged: _replace)
                  : null,
            );
          },
        ),
      ),
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.loading,
    required this.error,
    required this.empty,
    required this.done,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final bool empty;
  final bool done;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: AppColors.textMuted);
    final Widget child;
    if (loading) {
      child = const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (error != null) {
      child = TextButton(onPressed: onRetry, child: Text('$error，点击重试'));
    } else if (empty) {
      child = const Text('还没有评论，来抢沙发吧 ~', style: style);
    } else if (done) {
      child = const Text('没有更多了', style: style);
    } else {
      child = const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: child),
    );
  }
}

// ---------------------------------------------------------------- 单条评论

/// 一条评论：头像、昵称、时间与属地、点赞；正文；「N 条回复」。
/// 点击回复，长按弹出复制 / 回复 / 删除。
class CommentTile extends StatefulWidget {
  const CommentTile({
    super.key,
    required this.comment,
    required this.threadId,
    required this.onChanged,
    required this.onDeleted,
    required this.onReply,
    this.onOpenReplies,
    this.parentId,
  });

  final Comment comment;
  final String threadId;
  final ValueChanged<Comment> onChanged;
  final ValueChanged<Comment> onDeleted;
  final VoidCallback onReply;
  final VoidCallback? onOpenReplies;

  /// 楼中楼里所属的那条评论；回复它本身时不再显示「回复 @…」。
  final int? parentId;

  @override
  State<CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<CommentTile> {
  bool _liking = false;

  bool _ensureLogin() {
    if (AccountScope.read(context).isLoggedIn) return true;
    LoginPage.open(context);
    return false;
  }

  Future<void> _toggleLike() async {
    if (_liking || !_ensureLogin()) return;
    final c = widget.comment;
    final like = !c.liked;
    // 先改界面，失败再改回来。
    widget.onChanged(c.copyWith(liked: like, likedCount: c.likedCount + (like ? 1 : -1)));
    _liking = true;
    try {
      await AppScope.of(context).api.likeComment(widget.threadId, c.id, like);
    } catch (e) {
      widget.onChanged(c);
      AppScope.toast('点赞失败：${e is ApiException ? e.message : e}');
    } finally {
      _liking = false;
    }
  }

  Future<void> _delete() async {
    final c = widget.comment;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text('删除这条评论？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppScope.of(context).api.deleteComment(widget.threadId, c.id);
      widget.onDeleted(c);
      AppScope.toast('已删除');
    } catch (e) {
      AppScope.toast('删除失败：${e is ApiException ? e.message : e}');
    }
  }

  void _actions() {
    final c = widget.comment;
    final mine = AccountScope.read(context).profile?.userId == c.user.userId;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceHigh,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: AppColors.textPrimary),
              title: const Text('复制评论'),
              onTap: () {
                Navigator.of(sheet).pop();
                copyText(c.content, label: '评论');
              },
            ),
            freeCopyTile(sheet, c.content, label: '评论'),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded, color: AppColors.textPrimary),
              title: Text('复制昵称：${c.user.nickname}', maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.of(sheet).pop();
                copyText(c.user.nickname, label: '昵称');
              },
            ),
            ListTile(
              leading: const Icon(Icons.reply_rounded, color: AppColors.textPrimary),
              title: const Text('回复'),
              onTap: () {
                Navigator.of(sheet).pop();
                widget.onReply();
              },
            ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.negative),
                title: const Text('删除', style: TextStyle(color: AppColors.negative)),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _delete();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final reply = c.replyTo;
    final showReply = reply != null && reply.id != widget.parentId;
    void openUserPage() {
      if (c.user.userId > 0) openUser(context, c.user.userId, name: c.user.nickname);
    }

    return InkWell(
      onTap: widget.onReply,
      onLongPress: _actions,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 点头像 / 昵称进用户主页，长按头像看大图。
            GestureDetector(
              onTap: openUserPage,
              child: SizedBox(
                width: 36,
                child: ViewableImage(
                  url: c.user.avatarUrl,
                  title: c.user.nickname,
                  child: CoverArt(
                    palette: fallbackPalette('u${c.user.userId}'),
                    seed: 'u${c.user.userId}',
                    imageUrl: c.user.avatarUrl,
                    radius: 18,
                    icon: Icons.person_rounded,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: openUserPage,
                              child: Text(
                                c.user.nickname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            Text(
                              [formatCommentTime(c.time), ?c.location].join(' · '),
                              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      _LikeChip(liked: c.liked, count: c.likedCount, onTap: _toggleLike),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (showReply)
                            TextSpan(
                              text: '回复 @${reply.nickname}：',
                              style: const TextStyle(color: AppColors.accent),
                            ),
                          TextSpan(text: c.content),
                        ],
                      ),
                      style: const TextStyle(fontSize: 15, height: 1.5),
                    ),
                  ),
                  if (showReply && widget.parentId == null)
                    Container(
                      margin: const EdgeInsets.only(top: 8, right: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '@${reply.nickname}：${reply.content}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ),
                  if (widget.onOpenReplies case final open?)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: GestureDetector(
                        onTap: open,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '${formatPlayCount(c.replyCount)} 条回复 >',
                            style: const TextStyle(fontSize: 13, color: AppColors.accent),
                          ),
                        ),
                      ),
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

class _LikeChip extends StatelessWidget {
  const _LikeChip({required this.liked, required this.count, required this.onTap});

  final bool liked;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = liked ? AppColors.accent : AppColors.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (count > 0)
              Text(formatPlayCount(count), style: TextStyle(fontSize: 12, color: color)),
            const SizedBox(width: 4),
            Icon(
              liked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
              size: 16,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 楼中楼

/// 某条评论下的全部回复。[onChanged] 在楼主评论点赞状态变化时回调给外层列表。
Future<void> showFloorSheet(
  BuildContext context,
  String threadId,
  Comment parent, {
  required ValueChanged<Comment> onChanged,
}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: AppColors.surface,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _FloorSheet(threadId: threadId, parent: parent, onParentChanged: onChanged),
);

class _FloorSheet extends StatefulWidget {
  const _FloorSheet({required this.threadId, required this.parent, required this.onParentChanged});

  final String threadId;
  final Comment parent;
  final ValueChanged<Comment> onParentChanged;

  @override
  State<_FloorSheet> createState() => _FloorSheetState();
}

class _FloorSheetState extends State<_FloorSheet> {
  late Comment _parent = widget.parent;
  final _composerKey = GlobalKey<_ComposerState>();
  final List<Comment> _items = [];
  final Set<int> _seen = {};
  String? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _total = widget.parent.replyCount;
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await AppScope.of(context).api
          .floorComments(widget.threadId, _parent.id, cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.comments.where((c) => _seen.add(c.id)));
        _cursor = page.cursor;
        _hasMore = page.hasMore && page.comments.isNotEmpty;
        if (page.total > 0) _total = page.total;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _replace(Comment c) {
    if (c.id == _parent.id) {
      setState(() => _parent = c);
      widget.onParentChanged(c);
      return;
    }
    final i = _items.indexWhere((e) => e.id == c.id);
    if (i >= 0) setState(() => _items[i] = c);
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.85;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                '回复（${formatPlayCount(_total)}）',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.extentAfter < 400 && _hasMore && !_loading && _error == null) {
                    _loadMore();
                  }
                  return false;
                },
                child: ListView.builder(
                  itemCount: _items.length + 3,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return CommentTile(
                        comment: _parent,
                        threadId: widget.threadId,
                        onChanged: _replace,
                        onDeleted: (_) => Navigator.of(context).pop(),
                        onReply: () => _composerKey.currentState?.replyTo(null),
                      );
                    }
                    if (i == 1) {
                      return const Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text(
                          '全部回复',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      );
                    }
                    final k = i - 2;
                    if (k == _items.length) {
                      return _ListFooter(
                        loading: _loading,
                        error: _error,
                        empty: false,
                        done: !_hasMore,
                        onRetry: _loadMore,
                      );
                    }
                    final c = _items[k];
                    return CommentTile(
                      comment: c,
                      threadId: widget.threadId,
                      parentId: _parent.id,
                      onChanged: _replace,
                      onDeleted: (c) => setState(() => _items.removeWhere((e) => e.id == c.id)),
                      onReply: () => _composerKey.currentState?.replyTo(c),
                    );
                  },
                ),
              ),
            ),
            _Composer(
              key: _composerKey,
              threadId: widget.threadId,
              defaultReplyTo: _parent,
              onSent: (c, _) {
                if (c == null) return;
                if (_seen.add(c.id)) setState(() => _items.insert(0, c));
                setState(() => _total++);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 输入框

/// 底部输入框。[defaultReplyTo] 不为 null 时（楼中楼）默认回复那条评论。
class _Composer extends StatefulWidget {
  const _Composer({super.key, required this.threadId, required this.onSent, this.defaultReplyTo});

  final String threadId;
  final Comment? defaultReplyTo;

  /// 发送成功：新评论（接口没返回时为 null）和被回复的评论。
  final void Function(Comment? comment, Comment? replyTo) onSent;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  Comment? _replyTo;
  bool _sending = false;

  Comment? get _target => _replyTo ?? widget.defaultReplyTo;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 切换回复对象（null 表示回到默认）并弹出键盘。
  void replyTo(Comment? c) {
    setState(() => _replyTo = c);
    _focus.requestFocus();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    if (!AccountScope.read(context).isLoggedIn) {
      await LoginPage.open(context);
      return;
    }
    final target = _target;
    setState(() => _sending = true);
    try {
      final c = await AppScope.of(context).api
          .postComment(widget.threadId, text, replyTo: target?.id);
      if (!mounted) return;
      _input.clear();
      _focus.unfocus();
      setState(() => _replyTo = null);
      AppScope.toast(target == null ? '评论成功' : '回复成功');
      widget.onSent(c, target);
    } catch (e) {
      AppScope.toast('发送失败：${e is ApiException ? e.message : e}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceHigh,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      // 评论页不显示播放条，输入框直接贴底，要自己避开系统手势条。
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _focus,
                minLines: 1,
                maxLines: 4,
                maxLength: 140,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: target == null ? '说点什么吧' : '回复 @${target.user.nickname}',
                  border: InputBorder.none,
                  counterText: '',
                  isDense: true,
                ),
              ),
            ),
            if (_replyTo != null)
              IconButton(
                tooltip: '取消回复',
                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                onPressed: () => setState(() => _replyTo = null),
              ),
            ListenableBuilder(
              listenable: _input,
              builder: (context, _) => IconButton(
                tooltip: '发送',
                onPressed: _input.text.trim().isEmpty || _sending ? null : _send,
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, color: AppColors.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
