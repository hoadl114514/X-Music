import 'package:flutter/material.dart';

import '../app/app.dart';
import '../app/app_info.dart';
import '../audio/audio_cache.dart';
import '../audio/system_media.dart';
import '../data/format.dart';
import '../data/models.dart';
import '../state/account_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/share.dart';
import 'login_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final account = AccountScope.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => ListView(
        children: [
          const _Header('账号'),
          if (account.profile case final p?)
            ListTile(
              leading: const Icon(Icons.person_rounded),
              title: Text(p.nickname),
              subtitle: Text('UID ${p.userId}${p.vipType > 0 ? ' · 会员' : ''}'),
              trailing: TextButton(onPressed: account.logout, child: const Text('退出登录')),
            )
          else
            ListTile(
              leading: const Icon(Icons.login_rounded),
              title: const Text('登录账号'),
              subtitle: const Text('扫码或 Cookie；未登录时只能播放免费歌曲'),
              onTap: () => LoginPage.open(context),
            ),
          const _Header('播放'),
          ListTile(
            leading: const Icon(Icons.high_quality_rounded),
            title: const Text('默认音质'),
            subtitle: const Text('歌曲没有这一档时，自动选它有的最高档'),
            trailing: DropdownButton<AudioQuality>(
              value: settings.preferredQuality,
              underline: const SizedBox.shrink(),
              onChanged: (q) {
                if (q != null) settings.preferredQuality = q;
              },
              items: [
                for (final q in AudioQuality.values)
                  DropdownMenuItem(value: q, child: Text(q.label)),
              ],
            ),
          ),
          const _NotificationTile(),
          const _Header('歌词'),
          ListTile(
            leading: const Icon(Icons.lyrics_outlined),
            title: const Text('默认歌词来源'),
            subtitle: const Text('没有歌词时自动尝试另一个来源'),
            trailing: SegmentedButton<LyricSource>(
              segments: [
                for (final s in LyricSource.values) ButtonSegment(value: s, label: Text(s.label)),
              ],
              selected: {settings.lyricSource},
              showSelectedIcon: false,
              onSelectionChanged: (v) => settings.lyricSource = v.first,
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.translate_rounded),
            title: const Text('显示翻译'),
            value: settings.showTranslation,
            onChanged: (v) => settings.showTranslation = v,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.abc_rounded),
            title: const Text('显示罗马音'),
            value: settings.showRomaji,
            onChanged: (v) => settings.showRomaji = v,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.history_rounded),
            title: const Text('同步最近播放到网易云'),
            subtitle: const Text('登录后，听过的歌会出现在官方客户端的「最近播放」和听歌排行里'),
            value: settings.syncRecentPlays,
            onChanged: (v) => settings.syncRecentPlays = v,
          ),
          if (AppScope.of(context).audioCache case final cache?) ...[
            const _Header('缓存'),
            _AudioCacheTiles(cache),
          ],
          const _Header('关于'),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text(AppInfo.name),
            subtitle: const Text('版本 ${AppInfo.version} · 第三方客户端，与网易云音乐官方无关'),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: () => openUrl(AppInfo.repoUrl),
          ),
          if (AppScope.of(context).updates case final updates?)
            ListTile(
              leading: const Icon(Icons.system_update_rounded),
              title: const Text('检查更新'),
              onTap: () => updates.checkManually(context, AppScope.toast),
            ),
        ],
      ),
    );
  }
}

/// 通知关着时提示去打开：后台播放的媒体通知、控制中心和锁屏卡片都依赖它。
/// 从系统设置回来时重新检查。
class _NotificationTile extends StatefulWidget {
  const _NotificationTile();

  @override
  State<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends State<_NotificationTile> with WidgetsBindingObserver {
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final enabled = await SystemMediaBridge.notificationsEnabled();
    if (mounted && enabled != _enabled) setState(() => _enabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    if (_enabled) return const SizedBox.shrink();
    return const ListTile(
      leading: Icon(Icons.notifications_off_outlined, color: AppColors.accent),
      title: Text('通知权限未开启'),
      subtitle: Text('开启后通知栏、控制中心和锁屏才能显示播放控制'),
      trailing: Icon(Icons.chevron_right_rounded),
      onTap: SystemMediaBridge.openNotificationSettings,
    );
  }
}

/// 听歌缓存：上限、占用、清空。
class _AudioCacheTiles extends StatelessWidget {
  const _AudioCacheTiles(this.cache);

  final AudioCache cache;

  static const _presets = [1 << 30, 2 << 30, 5 << 30, 10 << 30, 20 << 30];

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: cache,
      builder: (context, _) {
        final limit = settings.audioCacheLimit;
        final used = cache.usedBytes;
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.sd_storage_outlined),
              title: const Text('听歌缓存上限'),
              subtitle: Text(limit <= 0 ? '已关闭：听歌不保存到本机' : '听过的歌存在本机，再听不耗流量；超出后先删最久没听的'),
              trailing: Text(limit <= 0 ? '关闭' : formatBytes(limit)),
              onTap: () => _pickLimit(context, limit),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('清空听歌缓存'),
              subtitle: Text('已用 ${formatBytes(used)}'),
              enabled: used > 0,
              onTap: () => _confirmClear(context, used),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickLimit(BuildContext context, int current) async {
    final settings = AppScope.of(context).settings;
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('听歌缓存上限'),
        children: [
          for (final v in [0, ..._presets])
            _LimitOption(
              label: v == 0
                  ? '关闭'
                  : '${formatBytes(v)}${v == AudioCache.defaultLimit ? '（默认）' : ''}',
              selected: v == current,
              onTap: () => Navigator.pop(context, v),
            ),
          _LimitOption(
            label: _presets.contains(current) || current <= 0
                ? '自定义…'
                : '自定义：${formatBytes(current)}',
            selected: !_presets.contains(current) && current > 0,
            onTap: () async {
              final custom = await _customLimit(context, current);
              if (custom != null && context.mounted) Navigator.pop(context, custom);
            },
          ),
        ],
      ),
    );
    if (picked == null) return;
    settings.audioCacheLimit = picked;
    await cache.prune();
  }

  /// 输入以 GB 为单位的上限，允许小数。
  Future<int?> _customLimit(BuildContext context, int current) {
    final controller = TextEditingController(
      text: current > 0 ? (current / (1 << 30)).toStringAsFixed(1) : '',
    );
    int? parse() {
      final gb = double.tryParse(controller.text.trim());
      if (gb == null || gb < 0.1 || gb > 1024) return null;
      return (gb * (1 << 30)).round();
    }

    return showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('自定义上限'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              suffixText: 'GB',
              helperText: '0.1 – 1024',
              errorText: controller.text.isEmpty || parse() != null ? null : '请输入 0.1 到 1024',
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (parse() case final v?) Navigator.pop(context, v);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            TextButton(
              onPressed: parse() == null ? null : () => Navigator.pop(context, parse()),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, int used) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空听歌缓存？'),
        content: Text('将删除 ${formatBytes(used)} 已缓存的歌曲，之后再听需要重新下载。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    await cache.clear();
    AppScope.toast('听歌缓存已清空');
  }
}

class _LimitOption extends StatelessWidget {
  const _LimitOption({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SimpleDialogOption(
      onPressed: onTap,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
            size: 20,
            color: selected ? AppColors.accent : null,
          ),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
      ),
    );
  }
}
