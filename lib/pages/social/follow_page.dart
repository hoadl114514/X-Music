import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../state/account_controller.dart';
import '../../theme/app_theme.dart';
import '../login_page.dart';
import '../music/nav.dart';
import 'compose_event_page.dart';
import 'event_card.dart';
import 'follow_list_page.dart';
import 'paged_list.dart';
import 'social_widgets.dart';

/// 抽屉里的「我的动态」。
class MyEventsPage extends StatelessWidget {
  const MyEventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final me = AccountScope.of(context).profile;
    if (me == null) return const _LoginPrompt(text: '登录后查看我的动态');
    return _MyEvents(key: ValueKey(me.userId), userId: me.userId);
  }
}

/// 我的动态列表，顶部是发动态入口，发完刷新。
class _MyEvents extends StatefulWidget {
  const _MyEvents({super.key, required this.userId});

  final int userId;

  @override
  State<_MyEvents> createState() => _MyEventsState();
}

class _MyEventsState extends State<_MyEvents> {
  final _list = GlobalKey<PagedListViewState<UserEvent>>();

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return PagedEvents(
      listKey: _list,
      empty: '还没有发过动态',
      load: (lasttime) => api.userEvents(widget.userId, lasttime: lasttime),
      header: [ComposeEventBar(onPosted: () => _list.currentState?.refresh())],
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_alt_rounded, size: 48, color: context.colors.textMuted),
          const SizedBox(height: 16),
          Text(text, style: TextStyle(color: context.colors.textSecondary)),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => LoginPage.open(context), child: const Text('去登录')),
        ],
      ),
    );
  }
}

/// 底部「关注」标签：上面一排关注的人，下面是关注的人的动态，可以只看音乐人或朋友。
class FollowPage extends StatelessWidget {
  const FollowPage({super.key});

  @override
  Widget build(BuildContext context) {
    final me = AccountScope.of(context).profile;
    if (me == null) return const _LoginPrompt(text: '登录后查看关注的人的动态');
    // 换账号时整个重建。
    return _Feed(key: ValueKey(me.userId), me: me);
  }
}

class _Feed extends StatefulWidget {
  const _Feed({super.key, required this.me});

  final UserProfile me;

  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> {
  final _list = GlobalKey<PagedListViewState<UserEvent>>();
  FollowScene _scene = FollowScene.all;
  bool _firstLoad = true;
  late Future<List<SocialUser>> _friends = _loadFriends();

  Future<List<SocialUser>> _loadFriends() =>
      AppScope.of(context).api.userFollows(widget.me.userId, limit: 20).then((p) => p.users);

  bool _match(UserEvent e) => switch (_scene) {
    FollowScene.all => true,
    FollowScene.musicians => e.user.musician,
    FollowScene.friends => !e.user.musician,
  };

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return PagedEvents(
      listKey: _list,
      load: (lasttime) {
        // 下拉刷新时（lasttime == -1）顺便刷新上面那排头像。
        if (lasttime == -1) {
          if (_firstLoad) {
            _firstLoad = false;
          } else {
            // 箭头函数会把 Future 当返回值交给 setState，这里必须用花括号。
            setState(() {
              _friends = _loadFriends();
            });
          }
        }
        return api.followFeed(lasttime: lasttime);
      },
      filter: _match,
      empty: switch (_scene) {
        FollowScene.all => '关注的人还没有发动态',
        FollowScene.musicians => '关注的音乐人还没有发动态',
        FollowScene.friends => '关注的朋友还没有发动态',
      },
      header: [
        ComposeEventBar(onPosted: () => _list.currentState?.refresh()),
        _FriendsRow(
          friends: _friends,
          onAll: () => FollowListPage.open(context, widget.me.userId, widget.me.nickname),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text('我的关注', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              for (final s in FollowScene.values) ...[
                if (s.index > 0)
                  SizedBox(
                    height: 14,
                    child: VerticalDivider(width: 1, color: context.colors.borderStrong),
                  ),
                TextButton(
                  onPressed: () => setState(() => _scene = s),
                  style: TextButton.styleFrom(
                    foregroundColor: s == _scene
                        ? context.colors.textPrimary
                        : context.colors.textMuted,
                    visualDensity: VisualDensity.compact,
                    textStyle: TextStyle(
                      fontSize: 15,
                      fontWeight: s == _scene ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  child: Text(s.label),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 一排关注的人的头像，最后是「全部好友」。
class _FriendsRow extends StatelessWidget {
  const _FriendsRow({required this.friends, required this.onAll});

  final Future<List<SocialUser>> friends;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: FutureBuilder<List<SocialUser>>(
        future: friends,
        builder: (context, snap) {
          final users = snap.data ?? const <SocialUser>[];
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            children: [
              for (final u in users)
                _RoundItem(
                  label: u.nickname,
                  onTap: () => openUser(context, u.userId, name: u.nickname),
                  child: SocialAvatar(userId: u.userId, url: u.avatarUrl, size: 64),
                ),
              _RoundItem(
                label: '全部好友',
                onTap: onAll,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: context.colors.borderStrong),
                  ),
                  child: Icon(Icons.more_horiz_rounded, color: context.colors.textSecondary),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RoundItem extends StatelessWidget {
  const _RoundItem({required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.panel),
      child: SizedBox(
        width: 80,
        child: Column(
          children: [
            child,
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
