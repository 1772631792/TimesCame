import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

const int kDiscoveryPort = 37020;
const int kDefaultHostPort = 37021;
const String kHostTag = 'TIMESCAM/HOST';
const String kDiscoverPayload = 'TIMESCAM/DISCOVER v1';

/// 只给一台电脑留够汇总时间：WiFi 里只有一台时，半秒内就连上。
const Duration kSettleWindow = Duration(milliseconds: 500);

enum LinkState { idle, scanning, choosing, connected, offline }

class HostInfo {
  const HostInfo({
    required this.name,
    required this.ip,
    required this.port,
    this.dir = '',
    this.id = '',
    this.hue = 262,
    this.photos = 0,
  });

  final String name;
  final String ip;
  final int port;
  final String dir;
  final String id;
  final int hue;
  final int photos;

  String get label => '$ip:$port';

  /// 有 id 用 id（换 IP 也认得），老版本没 id 就退回地址。
  String get key => id.isEmpty ? label : id;

  Uri uri(String path) => Uri.parse('http://$ip:$port$path');
}

class UploadResult {
  const UploadResult({
    required this.ok,
    this.file,
    this.ms = 0,
    this.speedMB = 0,
    this.error,
  });

  final bool ok;
  final String? file;
  final int ms;
  final double speedMB;
  final String? error;

  static UploadResult fail(String e) => UploadResult(ok: false, error: e);
}

/// 局域网发现 + 上传：UDP 广播找电脑，HTTP 直传照片。
///
/// 策略：
/// - WiFi 里只有一台电脑 → 500ms 内自动连上
/// - 有多台 → 进入 choosing，界面出头像列表让人点
/// - 上次连过的那台出现 → 立刻连，不再问
class NetClient extends ChangeNotifier {
  LinkState _state = LinkState.idle;
  HostInfo? _host;
  String _hint = '准备中…';
  int _latency = 0;

  String deviceName = '我的手机';
  String? preferredId;
  void Function(HostInfo host)? onHostPicked;

  LinkState get state => _state;
  HostInfo? get host => _host;
  String get hint => _hint;
  int get latency => _latency;

  final Map<String, HostInfo> _found = {};

  List<HostInfo> get candidates {
    final list = _found.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  RawDatagramSocket? _udp;
  StreamSubscription<RawSocketEvent>? _udpSub;
  Timer? _probeTimer;
  Timer? _pingTimer;

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 4)
    ..idleTimeout = const Duration(seconds: 20);

  bool _disposed = false;
  bool _adopting = false;
  bool _settled = false;
  bool _manual = false;
  int _fails = 0;
  int _probes = 0;
  DateTime? _startedAt;

  @override
  void dispose() {
    _disposed = true;
    _probeTimer?.cancel();
    _pingTimer?.cancel();
    _udpSub?.cancel();
    _udp?.close();
    _http.close(force: true);
    super.dispose();
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _setState(LinkState s, String hint) {
    _state = s;
    _hint = hint;
    _emit();
  }

  Future<void> startDiscovery({bool manual = false}) async {
    _pingTimer?.cancel();
    _probeTimer?.cancel();
    _found.clear();
    _host = null;
    _probes = 0;
    _fails = 0;
    _settled = false;
    _manual = manual;
    _startedAt = DateTime.now();

    _setState(LinkState.scanning, manual ? '正在搜索附近的电脑…' : '正在同一 WiFi 内寻找电脑…');
    try {
      await _openUdp();
    } catch (_) {
      _setState(LinkState.offline, '无法开启局域网广播，请检查 WiFi 是否可用');
      return;
    }

    _probe();
    _probeTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      _probe();
      _maybeSettle();
    });
  }

  Future<void> stopDiscovery() async {
    _probeTimer?.cancel();
    _probeTimer = null;
  }

  Future<void> _openUdp() async {
    if (_udp != null) return;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    _udp = socket;
    _udpSub = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg != null) _handlePacket(dg);
    });
  }

  void _probe() {
    final socket = _udp;
    if (socket == null) return;
    _probes++;
    try {
      socket.send(
        utf8.encode(kDiscoverPayload),
        InternetAddress('255.255.255.255'),
        kDiscoveryPort,
      );
    } catch (_) {
      // 广播被系统拒绝时不影响手动连接
    }
    if (_probes > 90) {
      _probeTimer?.cancel();
      if (_state != LinkState.connected) {
        _setState(LinkState.offline, '没找到电脑：确认两台设备连同一个 WiFi，并允许防火墙');
      }
    }
  }

  void _handlePacket(Datagram dg) {
    final text = utf8.decode(dg.data, allowMalformed: true).trim();
    if (!text.startsWith(kHostTag)) return;

    Map<String, dynamic> map;
    try {
      map = jsonDecode(text.substring(kHostTag.length).trim()) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final info = HostInfo(
      name: (map['name'] ?? '电脑').toString(),
      ip: dg.address.address,
      port: (map['port'] as num?)?.toInt() ?? kDefaultHostPort,
      dir: (map['dir'] ?? '').toString(),
      id: (map['id'] ?? '').toString(),
      hue: (map['hue'] as num?)?.toInt() ?? 262,
      photos: (map['count'] as num?)?.toInt() ?? 0,
    );

    final existing = _found[info.key];
    _found[info.key] = info;

    if (_state == LinkState.connected) {
      if (_host?.key == info.key) {
        _host = info; // 目录/张数可能变了
        _emit();
      }
      return;
    }

    if (existing != null && existing.label == info.label && _state == LinkState.choosing) {
      _emit();
      return;
    }

    // 上次那台：出现就立刻连，秒连的关键
    if (preferredId != null && preferredId == info.key && !_adopting) {
      unawaited(_adopt(info));
      return;
    }

    if (_state == LinkState.choosing) {
      _emit();
      return;
    }

    _maybeSettle();
  }

  void _maybeSettle() {
    if (_settled || _adopting || _state == LinkState.connected) return;
    final started = _startedAt;
    if (started == null) return;
    if (DateTime.now().difference(started) < kSettleWindow) return;
    if (_found.isEmpty) return;

    _settled = true;
    final pref = preferredId;
    if (pref != null && _found.containsKey(pref)) {
      unawaited(_adopt(_found[pref]!));
      return;
    }

    if (_found.length == 1 && !_manual) {
      unawaited(_adopt(_found.values.first));
      return;
    }

    _setState(
      LinkState.choosing,
      _found.length == 1 ? '找到 1 台电脑，点一下连上' : '发现 ${_found.length} 台电脑，选一台连上',
    );
  }

  Future<void> pick(HostInfo info) async {
    _settled = true;
    _probeTimer?.cancel();
    await _adopt(info);
  }

  Future<void> _adopt(HostInfo info) async {
    if (_adopting) return;
    _adopting = true;
    final sw = Stopwatch()..start();
    try {
      final res = await _getJson(info.uri('/ping')).timeout(const Duration(seconds: 2));
      sw.stop();
      if (res['ok'] != true) return;

      _latency = sw.elapsedMilliseconds;
      _host = info;
      _fails = 0;
      _probeTimer?.cancel();
      _probeTimer = null;
      _startPing();
      _setState(LinkState.connected, '已连接');
      onHostPicked?.call(info);
    } catch (_) {
      if (_found.length > 1) {
        _setState(LinkState.choosing, '连不上 ${info.name}（${info.label}），换一台试试');
      } else {
        _setState(LinkState.scanning, '发现了电脑，但 HTTP 连不上（放行防火墙后再试）');
      }
    } finally {
      _adopting = false;
    }
  }

  Future<bool> connectManual(String input) async {
    var text = input.trim();
    if (text.isEmpty) return false;
    text = text.replaceFirst('http://', '');
    final parts = text.split('/').first.split(':');
    final ip = parts.first;
    final port = parts.length > 1
        ? (int.tryParse(parts[1]) ?? kDefaultHostPort)
        : kDefaultHostPort;

    final ipOk = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(ip);
    if (!ipOk) {
      _setState(LinkState.idle, '地址格式：192.168.1.8 或 192.168.1.8:37021');
      return false;
    }

    _pingTimer?.cancel();
    _probeTimer?.cancel();
    _setState(LinkState.scanning, '正在连接 $ip:$port…');

    try {
      final probe = HostInfo(name: '电脑', ip: ip, port: port);
      final res = await _getJson(probe.uri('/info')).timeout(const Duration(seconds: 4));
      final info = HostInfo(
        name: (res['name'] ?? '电脑').toString(),
        ip: ip,
        port: port,
        dir: (res['dir'] ?? '').toString(),
        id: (res['id'] ?? '').toString(),
        hue: (res['hue'] as num?)?.toInt() ?? 262,
        photos: (res['count'] as num?)?.toInt() ?? 0,
      );
      _host = info;
      _found[info.key] = info;
      _settled = true;
      _fails = 0;
      _latency = 0;
      _startPing();
      _setState(LinkState.connected, '已连接');
      onHostPicked?.call(info);
      return true;
    } catch (_) {
      _setState(LinkState.offline, '连不上 $ip:$port（确认同一 WiFi 且放行防火墙）');
      return false;
    }
  }

  void forgetHost() {
    preferredId = null;
    _emit();
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      final h = _host;
      if (h == null) {
        timer.cancel();
        return;
      }
      final sw = Stopwatch()..start();
      try {
        final res = await _getJson(h.uri('/ping')).timeout(const Duration(seconds: 3));
        sw.stop();
        if (res['ok'] != true) throw const SocketException('bad reply');
        _latency = sw.elapsedMilliseconds;
        _fails = 0;
        _emit();
      } catch (_) {
        _fails++;
        if (_fails >= 3) {
          timer.cancel();
          _host = null;
          _setState(LinkState.offline, '和电脑断开了，正在重新寻找…');
          unawaited(startDiscovery());
        }
      }
    });
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final req = await _http.getUrl(uri);
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    final map = jsonDecode(body);
    if (map is! Map<String, dynamic>) throw const FormatException('bad json');
    return map;
  }

  Future<UploadResult> upload({
    required Uint8List bytes,
    required String name,
    void Function(double progress)? onProgress,
  }) async {
    final h = _host;
    if (h == null) return UploadResult.fail('未连接电脑');

    final sw = Stopwatch()..start();
    try {
      final req = await _http.postUrl(h.uri('/upload'));
      req.headers.set('X-File-Name', Uri.encodeComponent(name));
      req.headers.set('X-Device', Uri.encodeComponent(deviceName));
      req.headers.contentType = ContentType('image', 'jpeg');
      req.contentLength = bytes.length;

      const chunk = 128 * 1024;
      var sent = 0;
      Stream<List<int>> body() async* {
        while (sent < bytes.length) {
          final end = math.min(sent + chunk, bytes.length);
          final part = Uint8List.sublistView(bytes, sent, end);
          sent = end;
          yield part;
          onProgress?.call(sent / bytes.length);
        }
      }

      await req.addStream(body());
      final resp = await req.close();
      final raw = await resp.transform(utf8.decoder).join();
      sw.stop();

      if (resp.statusCode != 200) {
        return UploadResult.fail('电脑返回 ${resp.statusCode}');
      }
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['ok'] != true) {
        return UploadResult.fail((map['error'] ?? '电脑拒绝保存').toString());
      }
      return UploadResult(
        ok: true,
        file: (map['file'] ?? name).toString(),
        ms: (map['ms'] as num?)?.toInt() ?? sw.elapsedMilliseconds,
        speedMB: (map['speed'] as num?)?.toDouble() ?? 0,
      );
    } on SocketException {
      _fails++;
      return UploadResult.fail('网络中断，正在重连');
    } on TimeoutException {
      return UploadResult.fail('上传超时');
    } catch (e) {
      return UploadResult.fail('上传失败：$e');
    }
  }
}
