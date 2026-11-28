import 'package:flutter/foundation.dart';

import '../data/track_cache.dart';
import '../widgets/image_disk_cache.dart';
import 'audio_cache.dart';

/// 听歌缓存的总账：歌曲文件、图片，加上歌单、歌词、音质、账号和各列表的数据。
///
/// 设置页显示的占用和「清空听歌缓存」都按这三部分合计。
/// 歌曲文件按上限减去图片和数据后剩下的空间清理。
class ListenCache extends ChangeNotifier {
  ListenCache({required this.data});

  final DataCache data;

  /// 歌曲文件缓存。建好后再设上（它的上限要用到 [otherBytes]）。
  AudioCache? audio;

  int _images = 0;
  int _data = 0;

  /// 图片和数据占用的字节数（上次 [refresh] 时的值）。
  int get otherBytes => _images + _data;
  int get imageBytes => _images;
  int get dataBytes => _data;
  int get audioBytes => audio?.usedBytes ?? 0;
  int get usedBytes => audioBytes + otherBytes;

  /// 重新统计图片和数据的占用。
  Future<void> refresh() async {
    final (images, data) = await (ImageDiskCache.usedBytes(), this.data.store.usedBytes()).wait;
    if (images == _images && data == _data) return;
    _images = images;
    _data = data;
    notifyListeners();
  }

  /// 全部清空。内存里已经显示着的列表不受影响，下次进页面重新联网取。
  Future<void> clear() async {
    await audio?.clear();
    await ImageDiskCache.clear();
    await data.clear();
    _images = 0;
    _data = 0;
    notifyListeners();
  }
}
