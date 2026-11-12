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
import '../library/playlist_page.dart';
import '../library/track_list_view.dart';
import '../login_page.dart';
import '../music/nav.dart';
import 'paged_list.dart';
import 'social_widgets.dart';

/// 私信会话列表。右上角写新私信（从我的关注里选人）。
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  static Future<void> open(BuildContext context) => SubPage.push(context, const MessagesPage());

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final _list = GlobalKey<PagedListViewState<Conversation>>();

  Future<void> _chat(SocialUser user) async {
    await ChatPage.open(context, user);
    if (!mounted) return;
    // 对话页的 dispose 要等退出动画结束，这里先记上。
    ConversationReads.markRead(user.userId);
    // 红点按本地的已读记录先去掉；最后一条可能变了，再重新拉一遍。
    setState(() {});
    await _list.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return SubPage(
      title: '私信',
      actions: [
        IconButton(
          tooltip: '新私信',
          onPressed: () async {
            final user = await pickFollowedUser(context);
            if (user != null && context.mounted) await _chat(user);
          },
          icon: const Icon(Icons.edit_square),
        ),
      ],
      body: PagedListView<Conversation>(
        key: _list,
        empty: '还没有私信',
        loginHint: '登录后查看私信',
        load: (cursor) async {
          final offset = cursor as int? ?? 0;
          final page = await api.conversations(offset: offset);
          return (items: page.items, more: page.more, next: offset + page.items.length);
        },
        itemBuilder: (context, c, _) =>
            ConversationTile(conversation: c, onTap: () => _chat(c.user)),
      ),
    );
  }
}

class ConversationTile extends StatelessWidget {
  const ConversationTile({super.key, required this.conversation, required this.onTap});

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final unread = ConversationReads.unreadOf(c);
    return ListTile(
      leading: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: SocialAvatar(userId: c.user.userId, url: c.user.avatarUrl, size: 48),
      ),
      title: Text(c.user.nickname, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        c.preview.replaceAll('\n', ' '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      trailing: Text(
        formatCommentTime(c.time),
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
      onTap: onTap,
    );
  }
}

/// 本地的私信已读记录：用户 id → 最后一次退出和他对话的时间。
///
/// 服务端的未读数有时不会马上清零（或者根本没清），会话列表、抽屉里再拿到的还是旧数字；
/// 在这之前的消息一律当作已读，不显示红点。只在本次运行内有效。
abstract final class ConversationReads {
  static final _readAt = <int, DateTime>{};

  /// [latest] 是对话里看到的最新一条的时间（防本机时钟比服务器慢）。
  static void markRead(int userId, {DateTime? latest}) {
    final now = DateTime.now();
    final at = latest != null && latest.isAfter(now) ? latest : now;
    final old = _readAt[userId];
    if (old == null || at.isAfter(old)) _readAt[userId] = at;
  }

  /// [c] 应该显示的未读数。
  static int unreadOf(Conversation c) {
    final readAt = _readAt[c.user.userId];
    return readAt != null && !c.time.isAfter(readAt) ? 0 : c.unread;
  }

  @visibleForTesting
  static void reset() => _readAt.clear();
}

/// 从我的关注里选一个人（写新私信用）。没登录先去登录。
Future<SocialUser?> pickFollowedUser(BuildContext context) async {
  final me = AccountScope.read(context).profile;
  if (me == null) {
    await LoginPage.open(context);
    return null;
  }
  final api = AppScope.of(context).api;
  return Navigator.of(context).push(
    MaterialPageRoute<SocialUser>(
      builder: (context) => SubPage(
        title: '选择联系人',
        body: PagedListView<SocialUser>(
          header: const [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('我的关注', style: TextStyle(color: AppColors.textSecondary)),
            ),
          ],
          empty: '还没有关注任何人',
          load: (cursor) async {
            final offset = cursor as int? ?? 0;
            final page = await api.userFollows(me.userId, offset: offset);
            return (items: page.users, more: page.more, next: offset + page.users.length);
          },
          itemBuilder: (context, u, _) => SocialUserTile(
            user: u,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).pop(u),
          ),
        ),
      ),
    ),
  );
}

/// 和某人的私信对话。最新的在底部，往上滑加载更早的。
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.user});

  final SocialUser user;

  static Future<void> open(BuildContext context, SocialUser user) {
    if (!AccountScope.read(context).isLoggedIn) return LoginPage.open(context);
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => ChatPage(user: user)));
  }

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  /// 从旧到新。
  final _messages = <PrivateMessage>[];
  final _input = TextEditingController();
  bool _more = true;
  bool _loading = false;
  bool _sending = false;
  Object? _error;

  NeteaseApi get _api => AppScope.of(context).api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOlder());
  }

  @override
  void dispose() {
    // 看过了：之前的消息都算已读。
    ConversationReads.markRead(widget.user.userId, latest: _messages.lastOrNull?.time);
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadOlder() async {
    if (_loading || !_more) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.messageHistory(
        widget.user.userId,
        before: _messages.firstOrNull?.time,
      );
      if (!mounted) return;
      final known = {for (final m in _messages) m.id};
      setState(() {
        _messages.insertAll(0, page.messages.where((m) => !known.contains(m.id)));
        _more = page.more && page.messages.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final me = AccountScope.read(context).profile;
    if (me == null) return;
    setState(() => _sending = true);
    try {
      await _api.sendMessage(widget.user.userId, text);
      if (!mounted) return;
      _input.clear();
      setState(
        () => _messages.add(
          PrivateMessage(
            // 本地先占个位，id 用负数免得和接口里的撞上。
            id: -DateTime.now().microsecondsSinceEpoch,
            fromUserId: me.userId,
            time: DateTime.now(),
            text: text,
          ),
        ),
      );
    } on ApiException catch (e) {
      AppScope.toast('发送失败：${e.message}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = AccountScope.of(context).profile;
    final u = widget.user;
    final count = _messages.length + 1;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => openUser(context, u.userId, name: u.nickname),
          child: Text(u.nickname),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty && _error != null
                ? ErrorState(error: _error!, onRetry: _loadOlder)
                : NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      // 列表是倒过来的，extentAfter 就是离顶部还有多远。
                      if (n.metrics.extentAfter < 400) _loadOlder();
                      return false;
                    },
                    child: ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: count,
                      itemBuilder: (context, i) {
                        if (i == count - 1) return _topIndicator();
                        final m = _messages[_messages.length - 1 - i];
                        final prev = i + 1 < _messages.length
                            ? _messages[_messages.length - 2 - i]
                            : null;
                        // 隔了五分钟以上的消息上面显示时间。
                        final showTime =
                            prev == null || m.time.difference(prev.time).inMinutes >= 5;
                        return Column(
                          children: [
                            if (showTime)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  formatCommentTime(m.time),
                                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                              ),
                            _Bubble(message: m, mine: m.fromUserId == me?.userId, peer: u),
                          ],
                        );
                      },
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: '发私信给 ${u.nickname}',
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.surfaceHigh,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.panel),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '发送',
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, color: AppColors.accent),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topIndicator() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Center(
        child: TextButton(onPressed: _loadOlder, child: const Text('加载失败，点击重试')),
      );
    }
    if (_messages.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text('还没有聊过，打个招呼吧', style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, required this.peer});

  final PrivateMessage message;
  final bool mine;
  final SocialUser peer;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final width = MediaQuery.sizeOf(context).width * 0.68;
    final content = Column(
      crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (m.text.isNotEmpty)
          GestureDetector(
            onLongPress: () => showTextCopySheet(context, m.text, label: '私信'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: mine ? AppColors.accent : AppColors.cardHover,
                borderRadius: BorderRadius.circular(AppRadius.panel),
              ),
              child: Text(
                m.text,
                style: TextStyle(
                  fontSize: 15,
                  color: mine ? AppColors.onAccent : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        if (m.imageUrl case final url?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: GestureDetector(
              onTap: () => ImageViewerPage.open(context, url),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Image(
                  image: retryImage(sizedImage(url, 400)),
                  width: 160,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        if (m.song case final s?)
          _SharedCard(
            seed: 'song:${s.id}',
            coverUrl: s.coverUrl,
            title: s.title,
            subtitle: s.artist,
            onTap: () => PlayerScope.read(context).playQueue([s], title: '私信分享'),
          ),
        if (m.playlist case final p?)
          _SharedCard(
            seed: 'pl:${p.id}',
            coverUrl: p.coverUrl,
            title: p.name,
            subtitle: '歌单',
            onTap: () => SubPage.push(context, PlaylistPage(playlist: p)),
          ),
        if (m.album case final a?)
          _SharedCard(
            seed: 'al:${a.id}',
            coverUrl: a.coverUrl,
            title: a.name,
            subtitle: a.artist.isEmpty ? '专辑' : '专辑 · ${a.artist}',
            onTap: () => openAlbum(context, a.id, name: a.name),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
            SocialAvatar(
              userId: peer.userId,
              url: peer.avatarUrl,
              size: 36,
              onTap: () => openUser(context, peer.userId, name: peer.nickname),
            ),
            const SizedBox(width: 8),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: content,
          ),
        ],
      ),
    );
  }
}

class _SharedCard extends StatelessWidget {
  const _SharedCard({
    required this.seed,
    required this.coverUrl,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String seed;
  final String? coverUrl;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 40,
                  child: CoverArt(
                    palette: fallbackPalette(seed),
                    seed: seed,
                    imageUrl: coverUrl,
                    radius: 6,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
