import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/netease_api.dart';
import '../app/app.dart';
import '../data/models.dart';
import '../state/account_controller.dart';
import '../state/listen_together.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_art.dart';
import '../widgets/retry_image.dart';
import '../widgets/round_icon_button.dart';
import '../widgets/share.dart';
import 'login_page.dart';
import 'music/nav.dart';

/// 一起听：开房间、用邀请链接加入；在房间里时显示成员、邀请链接和正在放的歌。
class ListenTogetherPage extends StatelessWidget {
  const ListenTogetherPage({super.key});

  static Future<void> open(BuildContext context) =>
      SubPage.push(context, const ListenTogetherPage());

  @override
  Widget build(BuildContext context) {
    final listen = AppScope.of(context).listen;
    return ListenableBuilder(
      listenable: listen,
      builder: (context, _) => SubPage(
        title: '一起听',
        body: listen.active ? _InRoom(listen: listen) : _Lobby(listen: listen),
      ),
    );
  }
}

/// 出错时弹提示；没登录时去登录。
Future<void> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on ApiException catch (e) {
    if (e.code == 301 && context.mounted) return LoginPage.open(context);
    AppScope.toast('$e');
  } catch (e) {
    AppScope.toast('操作失败：$e');
  }
}

class _Lobby extends StatefulWidget {
  const _Lobby({required this.listen});

  final ListenTogether listen;

  @override
  State<_Lobby> createState() => _LobbyState();
}

class _LobbyState extends State<_Lobby> {
  final _link = TextEditingController();

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isNotEmpty) setState(() => _link.text = text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final text = Theme.of(context).textTheme;
    final listen = widget.listen;
    final loggedIn = AccountScope.of(context).isLoggedIn;
    final valid = ListenTogether.parseLink(_link.text) != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          color: scheme.primaryContainer,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.panel)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.headphones_rounded, size: 36, color: scheme.onPrimaryContainer),
                const SizedBox(height: 12),
                Text('开一个房间', style: text.titleLarge?.copyWith(color: scheme.onPrimaryContainer)),
                const SizedBox(height: 4),
                Text(
                  '你放什么，好友就听什么。好友用网易云音乐打开邀请链接即可加入。',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: listen.busy
                      ? null
                      : () => loggedIn ? _run(context, listen.createRoom) : LoginPage.open(context),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(loggedIn ? '创建房间' : '登录后创建'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.panel)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('加入好友的房间', style: text.titleLarge?.copyWith(color: scheme.onSurface)),
                const SizedBox(height: 4),
                Text(
                  '粘贴好友发来的一起听邀请链接。加入后会同步房间的歌单。',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _link,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'https://st.music.163.com/listen-together/…',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: '粘贴',
                      onPressed: _paste,
                      icon: const Icon(Icons.content_paste_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: listen.busy || !valid
                      ? null
                      : () => _run(context, () => listen.join(_link.text)),
                  child: const Text('加入'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InRoom extends StatelessWidget {
  const _InRoom({required this.listen});

  final ListenTogether listen;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final text = Theme.of(context).textTheme;
    final song = PlayerScope.of(context).current;
    final link = listen.inviteLink;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          listen.isHost ? '你是房主' : '已加入好友的房间',
          style: text.titleMedium?.copyWith(color: scheme.primary),
        ),
        const SizedBox(height: 4),
        Text(
          listen.isHost ? '你的切歌、暂停和进度会同步给房间里的人。' : '房间的歌单会自动同步。网易云没有公开房主的实时进度，所以不能精确同步到秒。',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Text('房间里的人', style: text.titleSmall?.copyWith(color: scheme.onSurface)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [for (final u in listen.users) _Member(user: u)],
        ),
        const SizedBox(height: 24),
        if (song != null)
          Card(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.panel)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: SizedBox(
                width: 56,
                child: CoverArt(
                  palette: song.palette,
                  seed: song.id,
                  imageUrl: song.coverUrl,
                  radius: AppRadius.small,
                ),
              ),
              title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text('正在一起听', style: TextStyle(color: scheme.primary)),
            ),
          ),
        if (listen.isHost && link != null) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () =>
                shareText('来和我一起听歌吧：$link', subject: '一起听', title: '邀请好友一起听', copied: '已复制邀请链接'),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('邀请好友'),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: listen.busy ? null : () => _run(context, listen.leave),
          icon: const Icon(Icons.logout_rounded),
          label: Text(listen.isHost ? '结束房间' : '退出房间'),
        ),
      ],
    );
  }
}

class _Member extends StatelessWidget {
  const _Member({required this.user});

  final SocialUser user;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final url = user.avatarUrl;
    return SizedBox(
      width: 64,
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: scheme.secondaryContainer,
            foregroundImage: url == null ? null : retryImage(url),
            child: Text(
              user.nickname.isEmpty ? '?' : user.nickname.characters.first,
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            user.nickname,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 播放页上的「一起听」按钮：在房间里时高亮并显示人数，点开一起听页面。
class ListenTogetherButton extends StatelessWidget {
  const ListenTogetherButton({super.key, required this.size, required this.iconSize});

  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final listen = AppScope.of(context).listen;
    return ListenableBuilder(
      listenable: listen,
      builder: (context, _) {
        final n = listen.users.length;
        return SizedBox(
          width: size + 16,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              RoundIconButton(
                icon: listen.active ? Icons.headphones_rounded : Icons.headphones_outlined,
                onPressed: () => ListenTogetherPage.open(context),
                tooltip: '一起听',
                color: listen.active ? context.colors.accent : Colors.white,
                size: size,
                iconSize: iconSize,
              ),
              if (listen.active && n > 0)
                Positioned(
                  left: size * 0.62,
                  top: size * 0.08,
                  child: IgnorePointer(
                    child: Text(
                      '$n',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.colors.accent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
