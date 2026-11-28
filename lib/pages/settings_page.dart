import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app.dart';
import '../app/app_info.dart';
import '../audio/audio_cache.dart';
import '../audio/audio_output.dart';
import '../audio/listen_cache.dart';
import '../audio/system_media.dart';
import '../data/format.dart';
import '../data/models.dart';
import '../state/account_controller.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/share.dart';
import 'login_page.dart';
import 'lyric_sources_page.dart';

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
          const _Header('外观'),
          const _AppearanceTiles(),
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
          ListTile(
            leading: const Icon(Icons.signal_cellular_alt_rounded),
            title: const Text('移动网络播放音质'),
            subtitle: const Text('用流量时请求这一档，省流量'),
            trailing: DropdownButton<AudioQuality?>(
              value: settings.mobileQuality,
              underline: const SizedBox.shrink(),
              onChanged: (q) => settings.mobileQuality = q,
              items: [
                const DropdownMenuItem(child: Text('同默认音质')),
                for (final q in AudioQuality.values)
                  DropdownMenuItem(value: q, child: Text(q.label)),
              ],
            ),
          ),
          const _NotificationTile(),
          const _Header('音频输出'),
          const _OutputTiles(),
          const _Header('歌词'),
          ListTile(
            leading: const Icon(Icons.lyrics_outlined),
            title: const Text('歌词来源'),
            subtitle: Text('按顺序获取：${LyricSourcesPage.summary(settings.lyricSources)}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => LyricSourcesPage.open(context),
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
          if (AppScope.of(context).listenCache case final cache?) ...[
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

/// 外观：主题模式、动态取色、主题色。
class _AppearanceTiles extends StatelessWidget {
  const _AppearanceTiles();

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final supported = AppScope.dynamicColorSupported(context);
    final useDynamic = supported && settings.dynamicColor;
    final scheme = context.scheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.dark_mode_outlined),
          title: const Text('主题'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SegmentedButton<AppThemeMode>(
              segments: [
                for (final m in AppThemeMode.values) ButtonSegment(value: m, label: Text(m.label)),
              ],
              selected: {settings.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (v) => settings.themeMode = v.first,
            ),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.wallpaper_rounded),
          title: const Text('动态取色'),
          subtitle: Text(supported ? '跟随系统壁纸的颜色' : '需要 Android 12 及以上'),
          value: useDynamic,
          onChanged: supported ? (v) => settings.dynamicColor = v : null,
        ),
        ListTile(
          enabled: !useDynamic,
          leading: const Icon(Icons.palette_outlined),
          title: const Text('主题色'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (name, color) in AppTheme.seeds)
                  _SeedSwatch(
                    name: name,
                    color: color,
                    selected: !useDynamic && settings.seedColor == color,
                    enabled: !useDynamic,
                    onTap: () => settings.seedColor = color,
                    ring: scheme.onSurface,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 一个主题色圆点：上半是种子色生成的 primary，下半是 tertiary，和系统壁纸取色的样式一致。
class _SeedSwatch extends StatelessWidget {
  const _SeedSwatch({
    required this.name,
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.ring,
  });

  final String name;
  final Color color;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    final s = ColorScheme.fromSeed(seedColor: color, brightness: Theme.of(context).brightness);
    return Tooltip(
      message: name,
      child: Semantics(
        button: true,
        selected: selected,
        label: name,
        child: InkResponse(
          onTap: enabled ? onTap : null,
          radius: 26,
          child: Opacity(
            opacity: enabled ? 1 : 0.38,
            child: Container(
              width: 44,
              height: 44,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? ring : Colors.transparent, width: 2),
              ),
              child: ClipOval(
                child: Column(
                  children: [
                    Expanded(
                      child: ColoredBox(color: s.primary, child: const SizedBox.expand()),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: ColoredBox(
                              color: s.secondaryContainer,
                              child: const SizedBox.expand(),
                            ),
                          ),
                          Expanded(
                            child: ColoredBox(color: s.tertiary, child: const SizedBox.expand()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
    return ListTile(
      leading: Icon(Icons.notifications_off_outlined, color: context.colors.accent),
      title: const Text('通知权限未开启'),
      subtitle: const Text('开启后通知栏、控制中心和锁屏才能显示播放控制'),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: SystemMediaBridge.openNotificationSettings,
    );
  }
}

/// 听歌缓存：上限、占用、清空。歌曲、图片和数据（歌单、歌词、列表）合在一起算。
class _AudioCacheTiles extends StatefulWidget {
  const _AudioCacheTiles(this.cache);

  final ListenCache cache;

  @override
  State<_AudioCacheTiles> createState() => _AudioCacheTilesState();
}

class _AudioCacheTilesState extends State<_AudioCacheTiles> {
  static const _presets = [1 << 30, 2 << 30, 5 << 30, 10 << 30, 20 << 30];

  ListenCache get cache => widget.cache;

  @override
  void initState() {
    super.initState();
    unawaited(cache.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: Listenable.merge([cache, ?cache.audio]),
      builder: (context, _) {
        final limit = settings.audioCacheLimit;
        final used = cache.usedBytes;
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.sd_storage_outlined),
              title: const Text('听歌缓存上限'),
              subtitle: Text(
                limit <= 0 ? '已关闭：歌曲不保存到本机，歌词和列表照常缓存' : '歌曲、图片、歌词和列表都存在本机，打开更快、少耗流量；超出后先删最久没听的歌',
              ),
              trailing: Text(limit <= 0 ? '关闭' : formatBytes(limit)),
              onTap: () => _pickLimit(context, limit),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('清空听歌缓存'),
              subtitle: Text(
                '已用 ${formatBytes(used)}（歌曲 ${formatBytes(cache.audioBytes)} · '
                '图片 ${formatBytes(cache.imageBytes)} · 数据 ${formatBytes(cache.dataBytes)}）',
              ),
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
    await cache.refresh();
    await cache.audio?.prune();
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
        content: Text('将删除 ${formatBytes(used)} 已缓存的歌曲、图片、歌词和列表，之后需要重新下载。'),
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
            color: selected ? context.colors.accent : null,
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
        style: TextStyle(color: context.colors.accent, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 音频输出：输出通道、位深、采样率、USB DAC 独占。改了立即应用。
class _OutputTiles extends StatelessWidget {
  const _OutputTiles();

  Future<void> _apply(BuildContext context) async {
    final settings = AppScope.of(context).settings;
    final result = await PlayerScope.read(context).applyOutput();
    if (result == null) return;
    if (result.bitDepth != settings.outputBitDepth.bits) {
      AppScope.toast('24 位输出需要 Android 12 及以上，已按 16 位输出');
    } else if (settings.usbExclusive && result.exclusive != ExclusiveState.on) {
      AppScope.toast(result.exclusive.message);
    } else if (!result.deviceFound) {
      AppScope.toast('没找到这个输出设备，先交给系统选择');
    }
  }

  Future<void> _pickDevice(BuildContext context) async {
    final settings = AppScope.of(context).settings;
    final devices = await PlayerScope.read(context).output?.devices() ?? const [];
    if (!context.mounted) return;
    final current = settings.outputDevice;
    final picked = await showModalBottomSheet<(AudioOutputDevice?,)>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.auto_mode_rounded),
                title: const Text('系统默认'),
                subtitle: const Text('跟随系统，插拔耳机自动切换'),
                trailing: current == null ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.of(context).pop((null,)),
              ),
              for (final d in {...devices, ?current})
                ListTile(
                  leading: Icon(_deviceIcon(d.type)),
                  title: Text(d.label),
                  subtitle: devices.contains(d) ? null : const Text('未连接'),
                  trailing: d == current ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.of(context).pop((d,)),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    settings.outputDevice = picked.$1;
    await _apply(context);
  }

  static IconData _deviceIcon(int type) => switch (type) {
    2 => Icons.speaker_phone_rounded,
    3 || 4 => Icons.headphones_rounded,
    8 || 26 || 27 => Icons.bluetooth_audio_rounded,
    11 || 12 || 22 => Icons.usb_rounded,
    9 || 10 => Icons.tv_rounded,
    _ => Icons.speaker_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final depth = settings.outputBitDepth;
    final fixedRate = depth.followsSourceRate;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.speaker_group_rounded),
          title: const Text('输出通道'),
          subtitle: Text(settings.outputDevice?.label ?? '系统默认'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _pickDevice(context),
        ),
        ListTile(
          leading: const Icon(Icons.graphic_eq_rounded),
          title: const Text('输出位深'),
          subtitle: Text(switch (depth) {
            OutputBitDepth.pcm16 => '高解析音源会降到 16 位',
            OutputBitDepth.pcm24 => '无损和高解析音源按 24 位输出（Android 12+）',
            OutputBitDepth.float32 => '只对 24 位以上的音源生效',
          }),
          trailing: DropdownButton<OutputBitDepth>(
            value: settings.outputBitDepth,
            underline: const SizedBox.shrink(),
            onChanged: (v) {
              if (v == null) return;
              settings.outputBitDepth = v;
              _apply(context);
            },
            items: [
              for (final v in OutputBitDepth.values)
                DropdownMenuItem(value: v, child: Text(v.label)),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.waves_rounded),
          title: const Text('输出采样率'),
          subtitle: Text(fixedRate ? '${depth.label}输出时跟随音源' : '不跟随音源时由播放器重采样'),
          enabled: !fixedRate,
          trailing: DropdownButton<int>(
            value: fixedRate ? 0 : settings.outputSampleRate,
            underline: const SizedBox.shrink(),
            onChanged: fixedRate
                ? null
                : (v) {
                    if (v == null) return;
                    settings.outputSampleRate = v;
                    _apply(context);
                  },
            items: [
              for (final r in AudioOutput.sampleRates)
                DropdownMenuItem(value: r, child: Text(AudioOutput.sampleRateLabel(r))),
            ],
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.usb_rounded),
          title: const Text('USB DAC 独占模式'),
          subtitle: const Text('绕过系统混音直通 DAC（bit-perfect）。需要 Android 14+，其他应用的声音会被静音'),
          value: settings.usbExclusive,
          onChanged: (v) {
            settings.usbExclusive = v;
            _apply(context);
          },
        ),
      ],
    );
  }
}
