import 'package:image_picker/image_picker.dart';

import '../app/app.dart';

/// 从相册选一张图，缩到 [maxSize] 以内，返回图片字节。用户取消或出错时返回 null（出错会提示）。
Future<List<int>?> pickImageBytes({double maxSize = 1080}) async {
  try {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: maxSize,
      maxHeight: maxSize,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    return await file.readAsBytes();
  } catch (e) {
    AppScope.toast('选择图片失败：$e');
    return null;
  }
}
