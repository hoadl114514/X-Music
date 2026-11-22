import 'package:flutter/material.dart';

import '../app/app.dart';
import '../theme/app_theme.dart';

/// 「待开发」小标签。
class DevBadge extends StatelessWidget {
  const DevBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.outline),
        borderRadius: BorderRadius.circular(AppRadius.tag),
      ),
      child: Text('待开发', style: TextStyle(fontSize: 11, color: context.colors.textMuted)),
    );
  }
}

/// 点到还没做的功能时的统一提示。
void showNotReady([String? feature]) => AppScope.toast('${feature ?? '该功能'}待开发');
