import 'package:flutter/material.dart';

import '../../api/netease_api.dart';
import '../../app/app.dart';
import '../../data/format.dart';
import '../../data/models.dart';
import '../../state/account_controller.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/copy_sheet.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/retry_image.dart';
import '../comments/comments_page.dart';
import '../library/playlist_page.dart';
import '../login_page.dart';
import '../music/nav.dart';
import 'paged_list.dart';
import 'social_widgets.dart';

/// 一条动态：作者、正文、配图、分享的歌 / 歌单 / 专辑、转发的原动态，底部评论和点赞。
class EventCard extends StatefulWidget {
  const EventCard({super.key, required this.event, this.onDeleted});

  final UserEvent event;

  /// 删除了自己的动态之后调用。
  final VoidCallback? onDeleted;

  @override
  State<EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<EventCard> {
  late UserEvent _event = widget.event;
  bool _liking = false;

  @override
  void didUpdateWidget(EventCard old) {
    super.didUpdateWidget(old);
    if (old.event != widget.event) _event = widget.event;
  }

  Future<void> _toggleLike() async {
    final thread = _event.threadId;
    if (thread == null || _liking) return;
    if (!AccountScope.read(context).isLoggedIn) {
      await LoginPage.open(context);
      return;
    }
    final before = _event;
    final like = !before.liked;
    setState(() {
      _liking = true;
      _event = before.copyWith(liked: like, likedCount: before.likedCount + (like ? 1 : -1));
    });
    try {
      await AppScope.of(context).api.likeEvent(thread, like);
    } on ApiException catch (e) {
      if (mounted) setState(() => _event = before);
      AppScope.toast('${like ? '点赞' : '取消点赞'}失败：${e.message}');
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  void _openComments() {
    final e = _event;
    final thread = e.threadId;
    if (thread == null) return;
    CommentsPage.open(
      context,
      target: CommentTarget.event,
      id: thread.substring(CommentTarget.event.prefix.length),
      title: '${e.user.nickname} 的动态',
      subtitle: e.text.isEmpty ? e.title : e.text.replaceAll('\n', ' '),
      coverUrl: e.pics.firstOrNull ?? e.user.avatarUrl,
    );
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text('确定删除这条动态吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppScope.of(context).api.deleteEvent(_event.id);
      AppScope.toast('已删除');
      widget.onDeleted?.call();
    } on ApiException catch (e) {
      AppScope.toast('删除失败：${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _event;
    final self = AccountScope.of(context).profile?.userId == e.user.userId;
    void openAuthor() => openUser(context, e.user.userId, name: e.user.nickname);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SocialAvatar(userId: e.user.userId, url: e.user.avatarUrl, size: 44, onTap: openAuthor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: openAuthor,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: e.user.nickname,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (e.action case final a?)
                                TextSpan(
                                  text: '  $a',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (self)
                      SizedBox(
                        height: 28,
                        child: PopupMenuButton<void>(
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          icon: const Icon(Icons.more_horiz_rounded, color: AppColors.textMuted),
                          itemBuilder: (_) => [
                            PopupMenuItem(onTap: _delete, child: const Text('删除动态')),
                          ],
                        ),
                      ),
                  ],
                ),
                Text(
                  formatCommentTime(e.time),
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                EventBody(event: e),
                if (e.forwarded case final f?) ...[const SizedBox(height: 8), _Forwarded(event: f)],
                _Actions(
                  event: e,
                  onComment: e.threadId == null ? null : _openComments,
                  onLike: e.threadId == null ? null : _toggleLike,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 动态正文：标题、文字、配图、分享的资源。
class EventBody extends StatelessWidget {
  const EventBody({super.key, required this.event});

  final UserEvent event;

  @override
  Widget build(BuildContext context) {
    final e = event;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (e.title case final t?)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        if (e.text.isNotEmpty)
          GestureDetector(
            onLongPress: () => showTextCopySheet(context, e.text, label: '动态'),
            child: Text(e.text, style: const TextStyle(fontSize: 15, height: 1.5)),
          ),
        if (e.pics.isNotEmpty) ...[const SizedBox(height: 8), _Pictures(urls: e.pics)],
        if (e.song case final s?) ...[
          const SizedBox(height: 8),
          _ResourceCard(
            seed: 'song:${s.id}',
            coverUrl: s.coverUrl,
            title: s.title,
            subtitle: s.artist,
            icon: Icons.play_circle_fill_rounded,
            onTap: () => PlayerScope.read(context).playQueue([s], title: '动态分享'),
          ),
        ],
        if (e.playlist case final p?) ...[
          const SizedBox(height: 8),
          _ResourceCard(
            seed: 'pl:${p.id}',
            coverUrl: p.coverUrl,
            title: p.name,
            subtitle: ['歌单', ?p.creator].join(' · '),
            onTap: () => SubPage.push(context, PlaylistPage(playlist: p)),
          ),
        ],
        if (e.album case final a?) ...[
          const SizedBox(height: 8),
          _ResourceCard(
            seed: 'al:${a.id}',
            coverUrl: a.coverUrl,
            title: a.name,
            subtitle: ['专辑', if (a.artist.isNotEmpty) a.artist].join(' · '),
            onTap: () => openAlbum(context, a.id, name: a.name),
          ),
        ],
      ],
    );
  }
}

class _Forwarded extends StatelessWidget {
  const _Forwarded({required this.event});

  final UserEvent event;

  @override
  Widget build(BuildContext context) {
    final e = event;
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: () => openUser(context, e.user.userId, name: e.user.nickname),
              child: Text(
                '@${e.user.nickname}${e.action == null ? '' : '  ${e.action}'}',
                style: const TextStyle(fontSize: 13, color: AppColors.accent),
              ),
            ),
            const SizedBox(height: 4),
            EventBody(event: e),
          ],
        ),
      ),
    );
  }
}

class _Pictures extends StatelessWidget {
  const _Pictures({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    Widget pic(String url, {BoxFit fit = BoxFit.cover}) => GestureDetector(
      onTap: () => ImageViewerPage.open(context, url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Image(
          image: retryImage(sizedImage(url, 600)),
          fit: fit,
          errorBuilder: (_, _, _) => Container(
            color: AppColors.cardHover,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
          ),
        ),
      ),
    );
    if (urls.length == 1) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260, maxWidth: 240),
          child: AspectRatio(aspectRatio: 3 / 4, child: pic(urls.single)),
        ),
      );
    }
    return GridView.count(
      crossAxisCount: urls.length == 2 || urls.length == 4 ? 2 : 3,
      crossAxisSpacing: 4,
      mainAxisSpacing: 4,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      children: [for (final u in urls.take(9)) pic(u)],
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.seed,
    required this.coverUrl,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon,
  });

  final String seed;
  final String? coverUrl;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: CoverArt(
                  palette: fallbackPalette(seed),
                  seed: seed,
                  imageUrl: coverUrl,
                  radius: 6,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (icon != null) Icon(icon, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.event, required this.onComment, required this.onLike});

  final UserEvent event;
  final VoidCallback? onComment;
  final VoidCallback? onLike;

  @override
  Widget build(BuildContext context) {
    String count(int n, String label) => n > 0 ? formatPlayCount(n) : label;
    final e = event;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _Action(
          icon: Icons.chat_bubble_outline_rounded,
          label: count(e.commentCount, '评论'),
          onTap: onComment,
        ),
        _Action(
          icon: e.liked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
          label: count(e.likedCount, '赞'),
          color: e.liked ? AppColors.accent : null,
          onTap: onLike,
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(foregroundColor: c, visualDensity: VisualDensity.compact),
      icon: Icon(icon, size: 18, color: c),
      label: Text(label, style: TextStyle(fontSize: 13, color: c)),
    );
  }
}

/// 某人的动态列表（「我的动态」、用户主页的「动态」标签）。
class UserEventList extends StatelessWidget {
  const UserEventList({super.key, required this.userId, this.empty = '还没有动态'});

  final int userId;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return PagedEvents(
      empty: empty,
      load: (lasttime) => api.userEvents(userId, lasttime: lasttime),
    );
  }
}

/// 按 lasttime 翻页的动态列表。
class PagedEvents extends StatelessWidget {
  const PagedEvents({
    super.key,
    required this.load,
    this.header = const [],
    this.filter,
    this.empty = '还没有动态',
    this.listKey,
  });

  final Future<EventPage> Function(int lasttime) load;
  final List<Widget> header;
  final bool Function(UserEvent e)? filter;
  final String empty;
  final GlobalKey<PagedListViewState<UserEvent>>? listKey;

  @override
  Widget build(BuildContext context) {
    return PagedListView<UserEvent>(
      key: listKey,
      header: header,
      filter: filter,
      empty: empty,
      loginHint: '登录后查看动态',
      separated: true,
      load: (cursor) async {
        final page = await load(cursor as int? ?? -1);
        return (items: page.events, more: page.more, next: page.lasttime);
      },
      itemBuilder: (context, e, remove) =>
          EventCard(key: ValueKey(e.id), event: e, onDeleted: remove),
    );
  }
}
