import 'dart:typed_data';
import 'dart:ui' as ui;

enum ShotState { queued, uploading, done, failed }

class Shot {
  Shot({
    required this.id,
    required this.name,
    required this.size,
    required this.at,
    this.data,
    this.thumb,
    this.localPath,
  });

  final String id;
  final String name;
  final int size;
  final DateTime at;

  Uint8List? data;
  Uint8List? thumb;
  String? localPath;

  ShotState state = ShotState.queued;
  double progress = 0;
  int? ms;
  double speedMB = 0;
  String? error;

  String get sizeText {
    if (size > 1024 * 1024) return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(size / 1024).toStringAsFixed(0)} KB';
  }
}

/// 生成 400px 宽的缩略图，避免相册页把原图全留在内存里。
Future<Uint8List?> makeThumb(Uint8List src, {int target = 400}) async {
  try {
    final codec = await ui.instantiateImageCodec(src, targetWidth: target);
    final frame = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    Uint8List? out;
    if (byteData != null) {
      out = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
    }
    frame.image.dispose();
    codec.dispose();
    return out;
  } catch (_) {
    return null;
  }
}

String two(int v) => v.toString().padLeft(2, '0');

String timeText(DateTime t) => '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';

/// 文件名：TimesCam_20261120_143012_812.jpg
String shotName(DateTime t) =>
    'TimesCam_${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}_${t.millisecond.toString().padLeft(3, '0')}.jpg';
