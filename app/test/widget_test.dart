import 'package:flutter_test/flutter_test.dart';
import 'package:times_cam/models.dart';

void main() {
  test('照片命名带毫秒，可直接排序', () {
    final name = shotName(DateTime(2026, 11, 20, 14, 30, 12, 812));
    expect(name, 'TimesCam_20261120_143012_812.jpg');
  });

  test('时间文本补零', () {
    expect(timeText(DateTime(2026, 1, 2, 3, 4, 5)), '03:04:05');
  });

  test('大小文本按 MB / KB 切换', () {
    final small = Shot(id: 'a', name: 'a.jpg', size: 2048, at: DateTime(2026));
    final big = Shot(id: 'b', name: 'b.jpg', size: 3 * 1024 * 1024, at: DateTime(2026));
    expect(small.sizeText, '2 KB');
    expect(big.sizeText, '3.0 MB');
  });
}
