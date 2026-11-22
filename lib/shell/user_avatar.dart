import 'package:flutter/material.dart';

import '../api/netease_api.dart';
import '../state/account_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/retry_image.dart';

/// 用户头像。登录后显示账号头像（加载前显示昵称首字），未登录显示人形图标。
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final profile = AccountScope.of(context).profile;
    final initial = profile == null || profile.nickname.isEmpty
        ? null
        : Text(
            profile.nickname.characters.first,
            style: TextStyle(
              fontSize: size * 0.48,
              fontWeight: FontWeight.w800,
              color: context.scheme.onPrimaryContainer,
              height: 1,
            ),
          );
    final px = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: profile == null
            ? context.scheme.secondaryContainer
            : context.scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: switch (profile?.avatarUrl) {
        final url? => Image(
          image: retryImage(sizedImage(url, px)),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => initial ?? const SizedBox.shrink(),
        ),
        null =>
          initial ??
              Icon(
                Icons.person_rounded,
                size: size * 0.6,
                color: context.scheme.onSecondaryContainer,
              ),
      },
    );
  }
}
