import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../state/settings.dart';
import '../widgets/share.dart';
import 'app_info.dart';

/// GitHub 上的一个正式版 Release。
class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.name,
    required this.notes,
    required this.url,
  });

  final String tag;
  final String name;
  final String notes;
  final String url;
}

/// 启动时查 GitHub 最新 Release，比当前版本新就弹窗提示。
///
/// 用 `releases/latest`，它不含预发布版本，所以 alpha / beta 不会提示。
class UpdateChecker {
  UpdateChecker({required this.settings, http.Client? client}) : _client = client ?? http.Client();

  final AppSettings settings;
  final http.Client _client;

  static final _latest = Uri.https('api.github.com', '/repos/${AppInfo.repo}/releases/latest');

  /// 最新正式版。请求失败返回 null。
  Future<ReleaseInfo?> fetchLatest() async {
    try {
      final res = await _client
          .get(_latest, headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final tag = '${j['tag_name'] ?? ''}';
      if (tag.isEmpty) return null;
      return ReleaseInfo(
        tag: tag,
        name: '${j['name'] ?? ''}'.trim().isEmpty ? tag : '${j['name']}',
        notes: '${j['body'] ?? ''}'.trim(),
        url: '${j['html_url'] ?? AppInfo.releasesUrl}',
      );
    } catch (_) {
      return null;
    }
  }

  /// 有比当前版本新的正式版时返回它。
  Future<ReleaseInfo?> newerRelease() async {
    final r = await fetchLatest();
    if (r == null || compareVersions(r.tag, AppInfo.version) <= 0) return null;
    return r;
  }

  /// 启动时调用：有新版且用户没跳过这个版本就弹窗。
  Future<void> checkOnLaunch(BuildContext context) async {
    final r = await newerRelease();
    if (r == null || r.tag == settings.skippedUpdate || !context.mounted) return;
    await showUpdateDialog(context, r, allowSkip: true);
  }

  /// 设置页「检查更新」。
  Future<void> checkManually(BuildContext context, void Function(String) toast) async {
    final latest = await fetchLatest();
    if (!context.mounted) return;
    if (latest == null) {
      toast('检查更新失败，请稍后再试');
    } else if (compareVersions(latest.tag, AppInfo.version) <= 0) {
      toast('已经是最新版本');
    } else {
      await showUpdateDialog(context, latest, allowSkip: false);
    }
  }

  Future<void> showUpdateDialog(BuildContext context, ReleaseInfo r, {required bool allowSkip}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 ${r.tag}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Text('当前版本 ${AppInfo.version}${r.notes.isEmpty ? '' : '\n\n${r.notes}'}'),
          ),
        ),
        actions: [
          if (allowSkip)
            TextButton(
              onPressed: () {
                settings.skippedUpdate = r.tag;
                Navigator.pop(ctx);
              },
              child: const Text('跳过此版本'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('以后再说')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openUrl(r.url);
            },
            child: const Text('去下载'),
          ),
        ],
      ),
    );
  }

  void dispose() => _client.close();
}

/// 比较两个版本号（可带 `v` 前缀和 `-alpha` 之类的后缀）。
///
/// 数字部分逐段比较，段数不限（`0.1.2.1` 比 `0.1.2` 新，缺的段当 0）；
/// 数字相同时，正式版比带后缀的预发布版新。
int compareVersions(String a, String b) {
  (List<int>, String) parse(String v) {
    final s = v.trim().replaceFirst(RegExp('^[vV]'), '').split('+').first;
    final dash = s.indexOf('-');
    final core = dash < 0 ? s : s.substring(0, dash);
    final pre = dash < 0 ? '' : s.substring(dash + 1);
    return (core.split('.').map((e) => int.tryParse(e) ?? 0).toList(), pre);
  }

  final (na, pa) = parse(a);
  final (nb, pb) = parse(b);
  for (var i = 0; i < max(na.length, nb.length); i++) {
    final x = i < na.length ? na[i] : 0;
    final y = i < nb.length ? nb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  if (pa == pb) return 0;
  if (pa.isEmpty) return 1;
  if (pb.isEmpty) return -1;
  return pa.compareTo(pb);
}
