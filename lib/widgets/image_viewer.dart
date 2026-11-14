import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api/netease_api.dart';
import '../app/app.dart';
import '../app/platform.dart';
import 'retry_image.dart';

const _channel = MethodChannel('netease_client/share');

/// 长按 [child] 打开看图页。[url] 为空时不响应长按。
class ViewableImage extends StatelessWidget {
  const ViewableImage({super.key, required this.url, required this.child, this.title});

  final String? url;
  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null) return child;
    return GestureDetector(
      onLongPress: () {
        unawaited(HapticFeedback.selectionClick());
        ImageViewerPage.open(context, u, title: title);
      },
      child: child,
    );
  }
}

/// 看图页：黑底全屏，双指缩放、双击放大，单击关闭；长按弹出「保存图片」。
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({super.key, required this.url, this.title});

  final String url;

  /// 保存时用作文件名的前缀（歌名、歌手名等）。
  final String? title;

  static Future<void> open(BuildContext context, String url, {String? title}) =>
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          opaque: false,
          barrierColor: Colors.black,
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 160),
          pageBuilder: (_, _, _) => ImageViewerPage(url: url, title: title),
          transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
        ),
      );

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> with SingleTickerProviderStateMixin {
  final _zoom = TransformationController();
  late final AnimationController _zoomAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..addListener(() => _zoom.value = _zoomTween?.evaluate(_zoomAnim) ?? _zoom.value);
  Matrix4Tween? _zoomTween;
  TapDownDetails? _doubleTapAt;

  String get _original => originalImage(widget.url);

  @override
  void dispose() {
    _zoom.dispose();
    _zoomAnim.dispose();
    super.dispose();
  }

  bool get _zoomed => _zoom.value.getMaxScaleOnAxis() > 1.01;

  void _toggleZoom() {
    final Matrix4 target;
    if (_zoomed) {
      target = Matrix4.identity();
    } else {
      final p = _doubleTapAt?.localPosition ?? Offset.zero;
      const s = 2.5;
      target = Matrix4.identity()
        ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
    _zoomTween = Matrix4Tween(begin: _zoom.value, end: target);
    _zoomAnim.forward(from: 0);
  }

  Future<void> _showActions() async {
    unawaited(HapticFeedback.selectionClick());
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('保存图片'),
              onTap: () => Navigator.of(context).pop('save'),
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('复制图片链接'),
              onTap: () => Navigator.of(context).pop('copy'),
            ),
          ],
        ),
      ),
    );
    if (action == 'save') {
      await saveImage(_original, title: widget.title);
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: _original));
      AppScope.toast('已复制图片链接');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              onLongPress: _showActions,
              onDoubleTapDown: (d) => _doubleTapAt = d,
              onDoubleTap: _toggleZoom,
              child: InteractiveViewer(
                transformationController: _zoom,
                minScale: 1,
                maxScale: 5,
                child: Center(child: _image()),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    tooltip: '关闭',
                    color: Colors.white,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '保存图片',
                    color: Colors.white,
                    icon: const Icon(Icons.download_rounded),
                    onPressed: () => saveImage(_original, title: widget.title),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 先显示已缓存的小图，原图加载好后替换。
  Widget _image() {
    final preview = Image(
      image: retryImage(widget.url),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) =>
          const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
    );
    return Image(
      image: retryImage(_original),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        final total = progress.expectedTotalBytes;
        return Stack(
          alignment: Alignment.center,
          children: [
            preview,
            SizedBox.square(
              dimension: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white70,
                value: total == null ? null : progress.cumulativeBytesLoaded / total,
              ),
            ),
          ],
        );
      },
      errorBuilder: (_, _, _) => widget.url == _original
          ? const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)
          : preview,
    );
  }
}

/// 下载图片并保存到系统相册（Android：Pictures/NeteaseClient），电脑上存到「下载」文件夹。
/// 其他平台复制图片链接。
Future<void> saveImage(String url, {String? title}) async {
  if (isNativeDesktop) return _saveToDownloads(url, title);
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    await Clipboard.setData(ClipboardData(text: url));
    AppScope.toast('当前平台不支持保存，已复制图片链接');
    return;
  }
  try {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final type = res.headers['content-type'] ?? '';
    final ext = type.contains('png') || url.toLowerCase().endsWith('.png')
        ? 'png'
        : type.contains('webp')
        ? 'webp'
        : 'jpg';
    final mime = ext == 'jpg' ? 'image/jpeg' : 'image/$ext';
    final name = '${imageFileStem(title)}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final saved = await _channel.invokeMethod<bool>('saveImage', {
      'bytes': res.bodyBytes,
      'name': name,
      'mime': mime,
    });
    AppScope.toast(saved == true ? '已保存到相册' : '需要存储权限，授权后再试一次');
  } on PlatformException catch (e) {
    AppScope.toast('保存失败：${e.message ?? e.code}');
  } on MissingPluginException {
    AppScope.toast('当前版本不支持保存图片');
  } catch (e) {
    AppScope.toast('保存失败：$e');
  }
}

Future<void> _saveToDownloads(String url, String? title) async {
  try {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final type = res.headers['content-type'] ?? '';
    final ext = type.contains('png') || url.toLowerCase().endsWith('.png')
        ? 'png'
        : type.contains('webp')
        ? 'webp'
        : 'jpg';
    final dir = await getDownloadsDirectory();
    if (dir == null) throw Exception('找不到下载文件夹');
    final name = '${imageFileStem(title)}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(res.bodyBytes);
    AppScope.toast('已保存到 ${file.path}');
  } catch (e) {
    AppScope.toast('保存失败：$e');
  }
}

/// 文件名前缀：去掉文件系统不允许的字符，过长截断。
@visibleForTesting
String imageFileStem(String? title) {
  final cleaned = (title ?? '')
      .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (cleaned.isEmpty) return 'netease';
  return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
}
