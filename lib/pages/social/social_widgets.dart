import 'package:flutter/material.dart';

import '../../api/netease_api.dart';
import '../../app/app.dart';
import '../../data/models.dart';
import '../../state/account_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cover_art.dart';
import '../login_page.dart';
import '../music/nav.dart';

/// 圆形用户头像，没有图时按 id 生成渐变底色。
class SocialAvatar extends StatelessWidget {
  const SocialAvatar({super.key, required this.userId, this.url, this.size = 44, this.onTap});

  final int userId;
  final String? url;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final avatar = SizedBox(
      width: size,
      child: CoverArt(
        palette: fallbackPalette('u$userId'),
        seed: 'u$userId',
        imageUrl: url,
        icon: Icons.person_rounded,
        radius: size / 2,
      ),
    );
    if (onTap == null) return avatar;
    return GestureDetector(onTap: onTap, child: avatar);
  }
}

/// 关注 / 取消关注按钮。未登录时点了去登录；看自己时不显示。
///
/// 传了 [artistId] 就关注歌手（`/api/artist/sub`，网页端叫「收藏」），否则关注用户。
/// 认证歌手的账号走用户关注会被风控拦下，所以有歌手 id 时优先用歌手 id。
class FollowButton extends StatefulWidget {
  const FollowButton({
    super.key,
    this.userId,
    this.artistId,
    required this.followed,
    this.compact = false,
    this.onChanged,
  }) : assert(userId != null || artistId != null);

  /// 账号 id。歌手没有入驻账号时为 null。
  final int? userId;

  /// 歌手 id。不为 null 时关注走歌手接口。
  final String? artistId;
  final bool followed;

  /// 列表里用的小号按钮。
  final bool compact;
  final ValueChanged<bool>? onChanged;

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  late bool _followed = widget.followed;
  bool _busy = false;

  @override
  void didUpdateWidget(FollowButton old) {
    super.didUpdateWidget(old);
    if (old.followed != widget.followed ||
        old.userId != widget.userId ||
        old.artistId != widget.artistId) {
      _followed = widget.followed;
    }
  }

  Future<void> _toggle() async {
    final account = AccountScope.read(context);
    final api = AppScope.of(context).api;
    if (!account.isLoggedIn) {
      await LoginPage.open(context);
      return;
    }
    if (_followed && !await _confirmUnfollow()) return;
    final next = !_followed;
    setState(() => _busy = true);
    try {
      if (widget.artistId case final aid?) {
        await api.setArtistFollowed(aid, next);
      } else {
        await api.setFollowed(widget.userId!, next);
      }
      if (!mounted) return;
      setState(() => _followed = next);
      widget.onChanged?.call(next);
      AppScope.toast(next ? '已关注' : '已取消关注');
    } on ApiException catch (e) {
      if (next && e.code == 250 && widget.artistId == null && mounted) {
        await _explainRiskControl();
      } else {
        AppScope.toast('${next ? '关注' : '取消关注'}失败：${e.message}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 网易云目前拦下了 App 以外的关注请求（code 250「关注异常」），网页版也一样，
  /// 取消关注不受影响。这里说明一下，免得用户以为是客户端坏了。
  Future<void> _explainRiskControl() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('暂时无法关注'),
      content: const Text(
        '网易云目前只允许在官方 App 里关注用户，网页版和第三方客户端发起的关注都会被拦下（提示「关注异常」）。\n\n'
        '请先在网易云音乐 App 里关注 TA。取消关注、查看关注列表等功能不受影响。',
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
    ),
  );

  Future<bool> _confirmUnfollow() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: const Text('确定不再关注 TA 吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('不再关注')),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final uid = widget.userId;
    final self = uid != null && AccountScope.of(context).profile?.userId == uid;
    if (self) return const SizedBox.shrink();
    final density = widget.compact ? VisualDensity.compact : VisualDensity.standard;
    final onPressed = _busy ? null : _toggle;
    if (_followed) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: context.colors.textSecondary,
          side: BorderSide(color: context.colors.borderStrong),
          visualDensity: density,
        ),
        child: const Text('已关注'),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('关注'),
      style: FilledButton.styleFrom(
        backgroundColor: context.colors.accent,
        foregroundColor: context.colors.onAccent,
        visualDensity: density,
      ),
    );
  }
}

/// 用户列表里的一行：头像、昵称、签名，右边关注按钮。点了进用户主页。
class SocialUserTile extends StatelessWidget {
  const SocialUserTile({super.key, required this.user, this.trailing, this.onTap});

  final SocialUser user;

  /// 不传时显示关注按钮。
  final Widget? trailing;

  /// 不传时进用户主页。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final u = user;
    return ListTile(
      leading: SocialAvatar(userId: u.userId, url: u.avatarUrl),
      title: Row(
        children: [
          Flexible(child: Text(u.nickname, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (u.musician) ...[
            const SizedBox(width: 4),
            Icon(Icons.verified_rounded, size: 14, color: context.colors.accent),
          ],
        ],
      ),
      subtitle: u.signature == null
          ? null
          : Text(
              u.signature!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.colors.textSecondary),
            ),
      trailing: trailing ?? FollowButton(userId: u.userId, followed: u.followed, compact: true),
      onTap: onTap ?? () => openUser(context, u.userId, name: u.nickname),
    );
  }
}
