import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/netease_api.dart';
import '../../app/app.dart';
import '../../data/models.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/retry_image.dart';
import '../library/track_list_view.dart';
import '../music/nav.dart';
import '../social/social_widgets.dart';

/// 用户主页名字下面的状态。
///
/// 看自己时可以点开设置状态、看和我状态相同的人；没设置时显示「添加状态」。
/// 看别人时只展示，状态带歌时点一下播放。
class UserStatusChip extends StatefulWidget {
  const UserStatusChip({super.key, required this.status, required this.editable});

  final UserStatus? status;
  final bool editable;

  @override
  State<UserStatusChip> createState() => _UserStatusChipState();
}

class _UserStatusChipState extends State<UserStatusChip> {
  late UserStatus? _status = widget.status;

  @override
  void didUpdateWidget(UserStatusChip old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) _status = widget.status;
  }

  Future<void> _onTap() async {
    if (widget.editable) {
      final next = await showStatusSheet(context, _status);
      if (next != null && mounted) setState(() => _status = next);
      return;
    }
    if (_status?.song case final song?) {
      unawaited(PlayerScope.read(context).playQueue([song], title: '状态里的歌'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final song = s?.song;
    final tappable = widget.editable || song != null;
    return Material(
      color: context.colors.card,
      shape: StadiumBorder(side: BorderSide(color: context.colors.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tappable ? _onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (s == null)
                Icon(Icons.add_rounded, size: 16, color: context.colors.textSecondary)
              else
                StatusIcon(url: s.iconUrl, size: 16),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  s == null ? '添加状态' : s.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: s == null ? context.colors.textSecondary : context.colors.textPrimary,
                  ),
                ),
              ),
              if (song != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.music_note_rounded, size: 14, color: context.colors.accent),
                Flexible(
                  child: Text(
                    '${song.title} - ${song.artist}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                  ),
                ),
              ],
              if (widget.editable && s != null) ...[
                const SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 16, color: context.colors.textMuted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 状态图标；没有图或加载失败时显示一个笑脸。
class StatusIcon extends StatelessWidget {
  const StatusIcon({super.key, required this.url, this.size = 24});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.emoji_emotions_outlined,
      size: size,
      color: context.colors.textSecondary,
    );
    final u = url;
    if (u == null) return fallback;
    return Image(
      image: RetryNetworkImage(u),
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

/// 设置状态的面板。设置成功后返回新状态，取消返回 null。
Future<UserStatus?> showStatusSheet(BuildContext context, UserStatus? current) =>
    showModalBottomSheet<UserStatus>(
      context: context,
      backgroundColor: context.colors.surfaceHigh,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _StatusSheet(current: current),
    );

class _StatusSheet extends StatefulWidget {
  const _StatusSheet({required this.current});

  final UserStatus? current;

  @override
  State<_StatusSheet> createState() => _StatusSheetState();
}

class _StatusSheetState extends State<_StatusSheet> {
  late Future<List<UserStatus>> _options = AppScope.of(context).api.statusOptions();
  bool _busy = false;

  Future<void> _pick(UserStatus option) async {
    var status = option;
    if (option.canEdit) {
      final text = await _editText(option);
      if (text == null || !mounted) return;
      status = option.copyWith(content: text);
    }
    final api = AppScope.of(context).api;
    setState(() => _busy = true);
    try {
      final hint = await api.setStatus(status);
      AppScope.toast(hint == null ? '状态已设置' : '状态已设置，$hint');
      if (mounted) Navigator.of(context).pop(status);
    } catch (e) {
      AppScope.toast('设置失败：${e is ApiException ? e.message : e}');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _editText(UserStatus option) => showDialog<String>(
    context: context,
    builder: (_) => _StatusTextDialog(option: option),
  );

  @override
  Widget build(BuildContext context) {
    final current = widget.current;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                current == null ? '设置状态' : '当前状态：${current.content}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            if (current != null)
              ListTile(
                leading: const Icon(Icons.people_outline_rounded),
                title: const Text('和我状态相同的人'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => SubPage.push(context, const SameStatusPage()),
              ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Flexible(
              child: FutureBuilder<List<UserStatus>>(
                future: _options,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return ErrorState(
                      error: snap.error!,
                      onRetry: () =>
                          setState(() => _options = AppScope.of(context).api.statusOptions()),
                    );
                  }
                  final list = snap.data;
                  if (list == null) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '暂时没有可以设置的状态',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.colors.textMuted),
                      ),
                    );
                  }
                  return GridView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 96,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.9,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, i) => _OptionTile(
                      option: list[i],
                      selected: current != null && list[i].type == current.type,
                      onTap: _busy ? null : () => _pick(list[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 自定义状态文字。控制器跟着对话框走，关闭动画期间不会用到已释放的控制器。
class _StatusTextDialog extends StatefulWidget {
  const _StatusTextDialog({required this.option});

  final UserStatus option;

  @override
  State<_StatusTextDialog> createState() => _StatusTextDialogState();
}

class _StatusTextDialogState extends State<_StatusTextDialog> {
  late final _controller = TextEditingController(text: widget.option.content);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('状态文字'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 20,
        decoration: InputDecoration(hintText: widget.option.desc ?? '写点什么'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        TextButton(
          onPressed: () {
            final text = _controller.text.trim();
            Navigator.of(context).pop(text.isEmpty ? null : text);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.option, required this.selected, required this.onTap});

  final UserStatus option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.panel),
        side: BorderSide(color: selected ? context.colors.accent : context.colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              StatusIcon(url: option.iconUrl, size: 32),
              const SizedBox(height: 6),
              Text(
                option.canEdit && option.content.isEmpty ? '自定义' : option.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              if (option.canEdit)
                Icon(Icons.edit_rounded, size: 12, color: context.colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// 和我状态相同的人。
class SameStatusPage extends StatefulWidget {
  const SameStatusPage({super.key});

  @override
  State<SameStatusPage> createState() => _SameStatusPageState();
}

class _SameStatusPageState extends State<SameStatusPage> {
  late Future<StatusRcmd> _data = AppScope.of(context).api.sameStatusUsers();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StatusRcmd>(
      future: _data,
      builder: (context, snap) {
        final d = snap.data;
        return SubPage(
          title: d?.title ?? '和我状态相同的人',
          body: snap.hasError
              ? ErrorState(
                  error: snap.error!,
                  onRetry: () => setState(() => _data = AppScope.of(context).api.sameStatusUsers()),
                )
              : d == null
              ? const Center(child: CircularProgressIndicator())
              : d.users.isEmpty
              ? Center(
                  child: Text('暂时没有状态相同的人', style: TextStyle(color: context.colors.textMuted)),
                )
              : ListView.builder(
                  itemCount: d.users.length,
                  itemBuilder: (context, i) => _StatusUserTile(user: d.users[i]),
                ),
        );
      },
    );
  }
}

class _StatusUserTile extends StatelessWidget {
  const _StatusUserTile({required this.user});

  final StatusUser user;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final lines = [?u.status?.content, ...u.tags];
    void open() => openUser(context, u.userId, name: u.nickname);
    return ListTile(
      leading: SocialAvatar(userId: u.userId, url: u.avatarUrl),
      title: Text(u.nickname, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: lines.isEmpty
          ? null
          : Text(
              lines.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.colors.textSecondary),
            ),
      trailing: u.status == null ? null : StatusIcon(url: u.status!.iconUrl),
      onTap: open,
    );
  }
}
