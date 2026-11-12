/// 播放量：`9876` → `9876`，`18000` → `1.8万`，`230000000` → `2.3亿`。
String formatPlayCount(int count) {
  if (count < 10000) return '$count';
  if (count < 100000000) return '${(count / 10000).toStringAsFixed(1)}万';
  return '${(count / 100000000).toStringAsFixed(1)}亿';
}

/// `mm:ss`，超过一小时为 `h:mm:ss`。负数按 0 处理。
String formatDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// 按小时给出问候语。
String greetingFor(DateTime time) {
  final h = time.hour;
  if (h < 5) return '夜深了';
  if (h < 11) return '上午好';
  if (h < 13) return '中午好';
  if (h < 18) return '下午好';
  return '晚上好';
}

/// 评论时间：刚刚 / 5分钟前 / 3小时前 / 昨天 14:05 / 3月8日 / 2021年12月8日。
String formatCommentTime(DateTime time, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(time);
  String two(int v) => v.toString().padLeft(2, '0');
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(time.year, time.month, time.day);
  if (day == today) return '${diff.inHours}小时前';
  if (today.difference(day).inDays == 1) return '昨天 ${two(time.hour)}:${two(time.minute)}';
  if (time.year == n.year) return '${time.month}月${time.day}日';
  return '${time.year}年${time.month}月${time.day}日';
}

/// 文件大小：`512 B`、`3.4 MB`、`1.2 GB`、`5 GB`（整数不带小数）。
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final text = i == 0 || v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
  return '$text ${units[i]}';
}
