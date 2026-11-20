import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'net_client.dart';

class Settings {
  bool autoSync = true;
  bool keepLocal = false;
  int resolution = 1;
  String deviceName = '我的手机';
  String manualHost = '';
  bool grid = false;
  bool flash = false;
  /// 画面顺时针旋转的 90° 次数（0~3）
  int rotate = 0;
  String hostId = '';
  String hostName = '';

  static const List<String> resolutionLabels = ['最高', '4K', '1080P', '720P'];
}

class AppState extends ChangeNotifier {
  AppState(this.net) {
    net.addListener(_onNet);
    net.onHostPicked = _rememberHost;
  }

  final NetClient net;
  final List<Shot> shots = [];

  Settings settings = Settings();

  final List<Shot> _queue = [];
  bool _draining = false;

  int sentCount = 0;
  int sentBytes = 0;
  int sentMs = 0;

  int get avgMs => sentCount == 0 ? 0 : (sentMs / sentCount).round();

  String get sentBytesText {
    if (sentBytes > 1024 * 1024) return '${(sentBytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(sentBytes / 1024).toStringAsFixed(0)} KB';
  }

  int get doneCount => shots.where((s) => s.state == ShotState.done).length;

  int get failedCount => shots.where((s) => s.state == ShotState.failed).length;

  int get queuedCount =>
      shots.where((s) => s.state == ShotState.queued || s.state == ShotState.failed).length;

  void _onNet() {
    net.deviceName = settings.deviceName;
    if (net.state == LinkState.connected) unawaited(_drain());
    notifyListeners();
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    settings = Settings()
      ..autoSync = p.getBool('autoSync') ?? true
      ..keepLocal = p.getBool('keepLocal') ?? false
      ..resolution = p.getInt('resolution') ?? 1
      ..deviceName = p.getString('deviceName') ?? '我的手机'
      ..manualHost = p.getString('manualHost') ?? ''
      ..grid = p.getBool('grid') ?? false
      ..flash = p.getBool('flash') ?? false
      ..rotate = (p.getInt('rotate') ?? 0) % 4
      ..hostId = p.getString('hostId') ?? ''
      ..hostName = p.getString('hostName') ?? '';
    net.deviceName = settings.deviceName;
    net.preferredId = settings.hostId.isEmpty ? null : settings.hostId;
    notifyListeners();
  }

  void _rememberHost(HostInfo host) {
    final id = host.id.isEmpty ? host.key : host.id;
    if (settings.hostId == id && settings.hostName == host.name) return;
    settings.hostId = id;
    settings.hostName = host.name;
    unawaited(saveSettings());
  }

  void forgetHost() {
    settings.hostId = '';
    settings.hostName = '';
    net.forgetHost();
    unawaited(saveSettings());
    notifyListeners();
  }

  Future<void> saveSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('autoSync', settings.autoSync);
    await p.setBool('keepLocal', settings.keepLocal);
    await p.setInt('resolution', settings.resolution);
    await p.setString('deviceName', settings.deviceName);
    await p.setString('manualHost', settings.manualHost);
    await p.setBool('grid', settings.grid);
    await p.setBool('flash', settings.flash);
    await p.setInt('rotate', settings.rotate);
    await p.setString('hostId', settings.hostId);
    await p.setString('hostName', settings.hostName);
    net.deviceName = settings.deviceName;
    net.preferredId = settings.hostId.isEmpty ? null : settings.hostId;
    notifyListeners();
  }

  Future<Shot> addShot({
    required Uint8List data,
    required String name,
    String? localPath,
  }) async {
    final shot = Shot(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      size: data.length,
      at: DateTime.now(),
      data: data,
      localPath: localPath,
    );
    shot.thumb = await makeThumb(data);
    shots.insert(0, shot);
    notifyListeners();

    if (settings.autoSync) {
      // 先排队：连着就马上传，没连就等连上再补传
      _queue.add(shot);
      unawaited(_drain());
    }
    return shot;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final shot = _queue.removeAt(0);
        if (shot.state == ShotState.done) continue;

        final data = shot.data;
        if (data == null) {
          shot.state = ShotState.failed;
          shot.error = '本地缓存已被清理，请重新拍摄';
          notifyListeners();
          continue;
        }
        if (net.state != LinkState.connected) {
          _queue.insert(0, shot);
          break;
        }

        shot.state = ShotState.uploading;
        shot.progress = 0;
        shot.error = null;
        notifyListeners();

        final result = await net.upload(
          bytes: data,
          name: shot.name,
          onProgress: (p) {
            shot.progress = p;
            notifyListeners();
          },
        );

        if (result.ok) {
          shot.state = ShotState.done;
          shot.progress = 1;
          shot.ms = result.ms;
          shot.speedMB = result.speedMB;
          shot.data = null;
          sentCount++;
          sentBytes += shot.size;
          sentMs += result.ms;
          if (!settings.keepLocal) unawaited(_removeLocal(shot));
        } else {
          shot.state = ShotState.failed;
          shot.error = result.error;
        }
        notifyListeners();
      }
    } finally {
      _draining = false;
    }
    notifyListeners();
  }

  Future<void> _removeLocal(Shot shot) async {
    final path = shot.localPath;
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 系统临时目录会被自动清理，删不掉也不影响
    }
  }

  void retry(Shot shot) {
    if (shot.state == ShotState.uploading || shot.state == ShotState.done) return;
    shot.state = ShotState.queued;
    shot.progress = 0;
    shot.error = null;
    if (!_queue.contains(shot)) _queue.insert(0, shot);
    notifyListeners();
    unawaited(_drain());
  }

  void retryFailed() => uploadAll();

  void uploadAll() {
    for (final s in shots) {
      if (s.state == ShotState.queued || s.state == ShotState.failed) {
        s.state = ShotState.queued;
        s.error = null;
        s.progress = 0;
        if (!_queue.contains(s)) _queue.add(s);
      }
    }
    notifyListeners();
    unawaited(_drain());
  }

  void clearSession() {
    shots.removeWhere((s) => s.state == ShotState.done);
    notifyListeners();
  }

  @override
  void dispose() {
    net.removeListener(_onNet);
    super.dispose();
  }
}
