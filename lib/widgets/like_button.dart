import 'package:flutter/material.dart';

import '../api/netease_api.dart';
import '../app/app.dart';
import '../state/account_controller.dart';
import '../theme/app_theme.dart';
import 'round_icon_button.dart';

/// 红心。状态来自账号的喜欢列表，未登录时点了提示登录。
class LikeButton extends StatelessWidget {
  const LikeButton({
    super.key,
    required this.songId,
    this.size = 40,
    this.iconSize = 22,
    this.color,
  });

  final String songId;
  final double size;
  final double iconSize;

  /// 未喜欢时的图标颜色。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    final liked = account.isLiked(songId);
    return RoundIconButton(
      icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      color: liked ? context.colors.accent : color,
      tooltip: liked ? '取消喜欢' : '喜欢',
      size: size,
      iconSize: iconSize,
      onPressed: () async {
        try {
          await account.toggleLike(songId);
        } on ApiException catch (e) {
          AppScope.toast(e.message);
        }
      },
    );
  }
}
