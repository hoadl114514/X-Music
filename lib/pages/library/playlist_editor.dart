import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../state/account_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/image_pick.dart';
import '../../widgets/playlist_card.dart';
import '../login_page.dart';
import '../social/compose_event_page.dart';
import 'playlist_page.dart';

/// 歌单名最长 40 个字，简介最长 1000 个字（和官方客户端一致）。
const _maxName = 40;
const _maxDescription = 1000;

/// 新建歌单：输入名称、选是否隐私。成功后进入新歌单。
Future<void> showCreatePlaylistDialog(BuildContext context) async {
  final account = AccountScope.read(context);
  if (!account.isLoggedIn) return LoginPage.open(context);
  final created = await showDialog<Playlist>(
    context: context,
    builder: (_) => const _CreateDialog(),
  );
  if (created == null || !context.mounted) return;
  AppScope.toast('已新建歌单「${created.name}」');
  await Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => PlaylistPage(playlist: created)));
}

class _CreateDialog extends StatefulWidget {
  const _CreateDialog();

  @override
  State<_CreateDialog> createState() => _CreateDialogState();
}

class _CreateDialogState extends State<_CreateDialog> {
  final _name = TextEditingController();
  bool _private = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final p = await AccountScope.read(context).createPlaylist(name, private: _private);
      if (!mounted) return;
      if (p == null) {
        // 接口没返回新歌单：列表已刷新，回到原页面即可。
        Navigator.of(context).pop();
        AppScope.toast('已新建歌单「$name」');
        return;
      }
      Navigator.of(context).pop(p);
    } catch (e) {
      AppScope.toast('新建失败：$e');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceHigh,
      title: const Text('新建歌单'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: _maxName,
            decoration: const InputDecoration(hintText: '输入歌单标题'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _private,
            onChanged: _busy ? null : (v) => setState(() => _private = v ?? false),
            title: const Text('设为隐私歌单'),
            subtitle: const Text('只有自己能看到', style: TextStyle(color: AppColors.textMuted)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy || _name.text.trim().isEmpty ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('完成'),
        ),
      ],
    );
  }
}

/// 自己歌单的「更多」菜单：编辑信息、分享到动态、删除。[onDeleted] 在删除成功后调用。
Future<void> showPlaylistManageSheet(
  BuildContext context,
  Playlist playlist, {
  VoidCallback? onDeleted,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceHigh,
    showDragHandle: true,
    builder: (sheet) {
      void then(Future<void> Function(BuildContext context) action) {
        final nav = Navigator.of(sheet);
        nav.pop();
        action(nav.context);
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
              title: const Text('编辑歌单信息'),
              subtitle: const Text('名称、简介、封面'),
              onTap: () => then((c) => PlaylistEditPage.open(c, playlist)),
            ),
            ListTile(
              leading: const Icon(Icons.campaign_outlined, color: AppColors.textPrimary),
              title: const Text('分享到动态'),
              onTap: () => then((c) => ComposeEventPage.open(c, playlist: playlist)),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.negative),
              title: const Text('删除歌单', style: TextStyle(color: AppColors.negative)),
              onTap: () => then((c) async {
                if (await deletePlaylistWithConfirm(c, playlist)) onDeleted?.call();
              }),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// 二次确认后删除歌单，成功返回 true。
Future<bool> deletePlaylistWithConfirm(BuildContext context, Playlist playlist) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: AppColors.surfaceHigh,
      title: const Text('删除歌单'),
      content: Text('确定删除「${playlist.name}」？删除后无法恢复。'),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
          onPressed: () => Navigator.of(c).pop(true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await AccountScope.read(context).deletePlaylist(playlist);
    AppScope.toast('已删除歌单「${playlist.name}」');
    return true;
  } catch (e) {
    AppScope.toast('删除失败：$e');
    return false;
  }
}

/// 编辑自己的歌单：封面、名称、简介。
class PlaylistEditPage extends StatefulWidget {
  const PlaylistEditPage({super.key, required this.playlist});

  final Playlist playlist;

  static Future<void> open(BuildContext context, Playlist playlist) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => PlaylistEditPage(playlist: playlist)));

  @override
  State<PlaylistEditPage> createState() => _PlaylistEditPageState();
}

class _PlaylistEditPageState extends State<PlaylistEditPage> {
  late final _name = TextEditingController(text: widget.playlist.name);
  late final _desc = TextEditingController(text: widget.playlist.description ?? '');
  List<int>? _cover;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  bool get _changed =>
      _cover != null ||
      _name.text.trim() != widget.playlist.name ||
      _desc.text.trim() != (widget.playlist.description ?? '');

  Future<void> _pickCover() async {
    final bytes = await pickImageBytes();
    if (bytes != null && mounted) setState(() => _cover = bytes);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      AppScope.toast('歌单名不能为空');
      return;
    }
    setState(() => _busy = true);
    try {
      await AccountScope.read(
        context,
      ).updatePlaylist(widget.playlist, name: name, description: _desc.text.trim(), cover: _cover);
      AppScope.toast('已保存');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      AppScope.toast('保存失败：$e');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.playlist;
    final cover = _cover;
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑歌单信息'),
        actions: [
          TextButton(
            onPressed: _busy || !_changed ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: _busy ? null : _pickCover,
              child: SizedBox(
                width: 160,
                height: 160,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cover != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.panel),
                        child: Image.memory(Uint8List.fromList(cover), fit: BoxFit.cover),
                      )
                    else
                      CoverArt(
                        palette: p.palette,
                        seed: p.id,
                        imageUrl: p.coverUrl,
                        fallbackImage: playlistCoverFallback(context, p),
                        radius: AppRadius.panel,
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(AppRadius.panel),
                          ),
                        ),
                        child: const Text(
                          '更换封面',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            enabled: !_busy,
            maxLength: _maxName,
            decoration: const InputDecoration(labelText: '名称'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _desc,
            enabled: !_busy,
            maxLength: _maxDescription,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: '简介',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }
}
