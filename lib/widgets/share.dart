import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app/app.dart';
import '../data/models.dart';

const _channel = MethodChannel('netease_client/share');

/// 歌曲的网页链接。
String songShareUrl(Song song) => 'https://music.163.com/#/song?id=${song.id}';

/// 用链接分享歌曲：Android 上弹系统分享面板，其他平台（或原生端不可用时）复制到剪贴板。
Future<void> shareSong(Song song) => shareText(
  songShareUrl(song),
  subject: '${song.title} - ${song.artist}',
  title: '分享歌曲',
  copied: '已复制歌曲链接',
);

/// 分享一段文字（通常是链接）：Android 上弹系统分享面板，其他平台复制到剪贴板并提示 [copied]。
Future<void> shareText(
  String text, {
  String subject = '',
  String title = '分享',
  String copied = '已复制链接',
}) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await _channel.invokeMethod<void>('shareText', {
        'text': text,
        'subject': subject,
        'title': title,
      });
      return;
    } on MissingPluginException {
      // 落到复制链接。
    } on PlatformException {
      // 同上。
    }
  }
  await Clipboard.setData(ClipboardData(text: text));
  AppScope.toast(copied);
}

/// 用浏览器打开链接：Android 上走系统，其他平台（或原生端不可用时）复制到剪贴板。
Future<void> openUrl(String url) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final ok = await _channel.invokeMethod<bool>('openUrl', {'url': url});
      if (ok ?? false) return;
    } on MissingPluginException {
      // 落到复制链接。
    } on PlatformException {
      // 同上。
    }
  }
  await Clipboard.setData(ClipboardData(text: url));
  AppScope.toast('已复制链接：$url');
}
