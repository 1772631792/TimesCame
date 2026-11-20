import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../models.dart';
import '../net_client.dart';
import '../theme.dart';
import '../widgets.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    required this.app,
    required this.active,
    required this.onBack,
    required this.onOpenShots,
  });

  final AppState app;
  final bool active;
  final VoidCallback onBack;
  final VoidCallback onOpenShots;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _cam;
  List<CameraDescription> _cameras = const [];
  final int _camIndex = 0;

  bool _ready = false;
  bool _busy = false;
  bool _booting = false;
  bool _grid = false;
  bool _torch = false;
  /// 画面顺时针旋转的次数，每次 90°
  int _rot = 0;
  bool _flashOn = false;
  String? _error;

  Offset? _focusAt;

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _grid = app.settings.grid;
    _torch = app.settings.flash;
    _rot = app.settings.rotate % 4;
    unawaited(_boot());
  }

  @override
  void didUpdateWidget(covariant CameraPage old) {
    super.didUpdateWidget(old);
    if (old.active == widget.active) return;
    final c = _cam;
    if (c == null || !c.value.isInitialized) {
      if (widget.active && _error != null) unawaited(_boot());
      return;
    }
    try {
      if (widget.active) {
        unawaited(c.resumePreview());
      } else {
        unawaited(c.pausePreview());
      }
    } catch (_) {
      // 部分机型不支持暂停预览，忽略即可
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _cam;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(c.dispose().then((_) {
        if (mounted) setState(() => _ready = false);
      }));
      _cam = null;
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_boot());
    }
  }

  Future<void> _boot() async {
    if (_booting || _busy) return;
    _booting = true;
    if (mounted) {
      setState(() {
        _error = null;
        _ready = false;
      });
    }
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (_cameras.isEmpty) {
        setState(() => _error = '这台设备上没有找到摄像头');
        return;
      }
      final desc = _cameras[_camIndex % _cameras.length];
      final controller = CameraController(
        desc,
        _preset(app.settings.resolution),
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();

      // 换镜头后要重新点灯；前摄通常没有补光灯
      var torchOk = true;
      try {
        await controller.setFlashMode(_torch ? FlashMode.torch : FlashMode.off);
      } catch (_) {
        torchOk = false;
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }
      await _cam?.dispose();
      setState(() {
        _cam = controller;
        _ready = true;
      });

      if (!torchOk && _torch) {
        _torch = false;
        app.settings.flash = false;
        unawaited(app.saveSettings());
        if (mounted) {
          setState(() {});
          _toast('这颗镜头没有补光灯，已自动关灯');
        }
      }
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = _hint(e));
    } catch (e) {
      if (mounted) setState(() => _error = '相机启动失败：$e');
    } finally {
      _booting = false;
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(milliseconds: 1800),
        ),
      );
  }

  String _hint(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
        return '没有相机权限，请在系统设置里允许 TimesCam 使用相机';
      case 'CameraAccessRestricted':
        return '相机被系统限制，暂不可用';
      default:
        return '相机异常：${e.description ?? e.code}';
    }
  }

  ResolutionPreset _preset(int q) {
    switch (q) {
      case 0:
        return ResolutionPreset.max;
      case 1:
        return ResolutionPreset.veryHigh;
      case 2:
        return ResolutionPreset.high;
      default:
        return ResolutionPreset.medium;
    }
  }

  /// 画面顺时针转 90°：预览和拍出来的照片一起转，转满一圈回到 0。
  Future<void> _rotate90() async {
    HapticFeedback.selectionClick();
    setState(() => _rot = (_rot + 1) % 4);
    app.settings.rotate = _rot;
    unawaited(app.saveSettings());
    _toast('画面已顺时针转 90°（共 ${_rot * 90}°）');
  }

  /// 开关手机补光灯（常亮手电筒）。
  Future<void> _toggleTorch() async {
    final next = !_torch;
    final c = _cam;
    try {
      if (c != null && c.value.isInitialized) {
        await c.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      }
    } on CameraException catch (e) {
      _toast(e.code.contains('NotSupported') || e.code.contains('Flash')
          ? '这颗镜头没有补光灯（前摄一般没有）'
          : '开灯失败：${e.description ?? e.code}');
      return;
    } catch (_) {
      _toast('这颗镜头没有补光灯');
      return;
    }

    _torch = next;
    app.settings.flash = next;
    unawaited(app.saveSettings());
    HapticFeedback.selectionClick();
    if (mounted) setState(() {});
  }

  Future<void> _shoot() async {
    final c = _cam;
    if (_busy || c == null || !c.value.isInitialized) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      final file = await c.takePicture();
      var bytes = await file.readAsBytes();
      if (_rot != 0) {
        bytes = await _rotateJpeg(bytes, _rot);
        // 本地缓存文件也转过来，保留本地副本时和预览方向一致
        try {
          await File(file.path).writeAsBytes(bytes);
        } catch (_) {
          // 临时文件写不进就算了，上传用的仍是转好的数据
        }
      }
      final now = DateTime.now();
      unawaited(app.addShot(data: bytes, name: shotName(now), localPath: file.path));
      if (mounted) {
        setState(() => _flashOn = true);
        await Future<void>.delayed(const Duration(milliseconds: 90));
        if (mounted) setState(() => _flashOn = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拍照失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 顺时针旋转 JPEG（turns 个 90°）。4K 图解码比较重，丢到后台 isolate，别卡住取景。
  Future<Uint8List> _rotateJpeg(Uint8List bytes, int turns) {
    return Isolate.run(() {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;
      final rotated = img.copyRotate(decoded, angle: turns * 90);
      return Uint8List.fromList(img.encodeJpg(rotated, quality: 92));
    });
  }

  Future<void> _pickFromAlbum() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (picked == null) return;
      final Uint8List bytes = await picked.readAsBytes();
      await app.addShot(
        data: bytes,
        name: shotName(DateTime.now()),
        localPath: picked.path,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败：$e')),
        );
      }
    }
  }

  Future<void> _tapFocus(TapDownDetails details, Size size) async {
    final c = _cam;
    if (c == null) return;
    var dx = (details.localPosition.dx / size.width).clamp(0.0, 1.0);
    var dy = (details.localPosition.dy / size.height).clamp(0.0, 1.0);
    // 画面转过之后，点击位置要换算回传感器原始坐标，否则对焦点会跑偏
    if (_rot != 0) {
      final t = dx;
      switch (_rot) {
        case 1:
          dx = dy;
          dy = 1 - t;
        case 2:
          dx = 1 - t;
          dy = 1 - dy;
        case 3:
          dx = 1 - dy;
          dy = t;
      }
    }
    setState(() => _focusAt = details.localPosition);
    Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _focusAt = null);
    });
    try {
      await c.setFocusPoint(Offset(dx, dy));
      await c.setFocusMode(FocusMode.auto);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cam?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTapDown: (d) => _tapFocus(d, size),
            child: _preview(),
          ),
          const _Vignette(),
          if (_grid) const _GridLines(),

          // 顶部：Stack 是 expand，必须靠 Align 收到顶部，否则整行会被拉满高度、按钮跑到屏幕中间
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        GlassIconButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onTap: widget.onBack,
                          size: 54,
                        ),
                        const Spacer(),
                        GlassIconButton(
                          icon: Icons.rotate_90_degrees_cw_rounded,
                          color: _rot == 0 ? Palette.text : Palette.accent,
                          onTap: _rotate90,
                          size: 54,
                        ),
                        const SizedBox(width: 10),
                        GlassIconButton(
                          icon: _torch ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                          color: _torch ? Palette.warn : Palette.text,
                          onTap: _toggleTorch,
                          size: 54,
                        ),
                        const SizedBox(width: 10),
                        GlassIconButton(
                          icon: _grid ? Icons.grid_on_rounded : Icons.grid_3x3_rounded,
                          color: _grid ? Palette.accent : Palette.text,
                          onTap: () {
                            _grid = !_grid;
                            app.settings.grid = _grid;
                            unawaited(app.saveSettings());
                            setState(() {});
                          },
                          size: 54,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _UploadStatus(app: app),
                  ],
                ),
              ),
            ),
          ),

          if (_focusAt != null)
            Positioned(
              left: _focusAt!.dx - 34,
              top: _focusAt!.dy - 34,
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Palette.warn.withValues(alpha: 0.9), width: 1.6),
                ),
              ),
            ),

          // 拍照白闪层：ColoredBox 本身是 opaque 命中测试，透明度为 0 时也会吃掉点击，必须 IgnorePointer
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _flashOn ? 1 : 0,
              duration: const Duration(milliseconds: 90),
              child: const ColoredBox(color: Colors.white),
            ),
          ),

          if (_error != null) _ErrorBox(message: _error!, onRetry: _boot, onBack: widget.onBack),

          // 底部
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomBar(
              app: app,
              busy: _busy,
              ready: _ready,
              onShoot: _shoot,
              onAlbums: _pickFromAlbum,
              onOpenShots: widget.onOpenShots,
              canOpenShots: app.shots.isNotEmpty,
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview() {
    final c = _cam;
    if (c == null || !c.value.isInitialized) {
      if (_error != null) return const SizedBox.expand();
      return const Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: Palette.accent),
        ),
      );
    }
    final preview = c.value.previewSize;
    final view = preview == null
        ? CameraPreview(c)
        : FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: preview.height,
              height: preview.width,
              child: CameraPreview(c),
            ),
          );
    if (_rot == 0) return view;
    return RotatedBox(quarterTurns: _rot, child: view);
  }
}

class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.black.withValues(alpha: 0.55),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.78),
            ],
            stops: const [0.0, 0.2, 0.62, 1.0],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      ),
    );
  }
}

class _GridLines extends StatelessWidget {
  const _GridLines();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _GridPainter(), size: Size.infinite),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _UploadStatus extends StatelessWidget {
  const _UploadStatus({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final online = app.net.state == LinkState.connected;
        Shot? latest;
        for (final s in app.shots) {
          if (s.state == ShotState.uploading || s.state == ShotState.failed) {
            latest = s;
            break;
          }
          latest ??= s;
          if (s.state == ShotState.done) break;
        }

        String text;
        Color color;
        IconData icon;

        if (!online) {
          text = '未连接 · 先存在手机';
          color = Palette.warn;
          icon = Icons.cloud_off_rounded;
        } else if (latest?.state == ShotState.uploading) {
          text = '同步中 ${(latest!.progress * 100).round()}%';
          color = Palette.accent;
          icon = Icons.sync_rounded;
        } else if (latest?.state == ShotState.failed) {
          text = '上传失败，可重试';
          color = Palette.err;
          icon = Icons.error_outline_rounded;
        } else if (latest?.state == ShotState.done) {
          text = '已同步 · ${latest!.ms ?? 0} ms';
          color = Palette.ok;
          icon = Icons.cloud_done_rounded;
        } else {
          text = '就绪';
          color = Palette.ok;
          icon = Icons.bolt_rounded;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.app,
    required this.busy,
    required this.ready,
    required this.onShoot,
    required this.onAlbums,
    required this.onOpenShots,
    required this.canOpenShots,
  });

  final AppState app;
  final bool busy;
  final bool ready;
  final VoidCallback onShoot;
  final VoidCallback onAlbums;
  final VoidCallback onOpenShots;
  final bool canOpenShots;

  @override
  Widget build(BuildContext context) {
    final last = app.shots.isEmpty ? null : app.shots.first;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.72)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SideButton(
            onTap: onAlbums,
            child: const Icon(Icons.photo_library_rounded, color: Colors.white, size: 22),
          ),
          _Shutter(busy: busy, enabled: ready, onTap: onShoot),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canOpenShots ? onOpenShots : null,
            child: Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.4),
                color: Colors.white.withValues(alpha: 0.08),
              ),
              clipBehavior: Clip.antiAlias,
              child: last?.thumb != null
                  ? Image.memory(last!.thumb!, fit: BoxFit.cover, cacheWidth: 160)
                  : Icon(
                      Icons.photo_rounded,
                      color: Colors.white.withValues(alpha: 0.75),
                      size: 22,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withValues(alpha: 0.1),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _Shutter extends StatefulWidget {
  const _Shutter({required this.busy, required this.enabled, required this.onTap});

  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_Shutter> createState() => _ShutterState();
}

class _ShutterState extends State<_Shutter> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final scale = _down ? 0.92 : 1.0;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.enabled && !widget.busy ? widget.onTap : null,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 110),
        child: Container(
          width: 86,
          height: 86,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.75), width: 3),
            color: Colors.white.withValues(alpha: 0.06),
          ),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: widget.busy ? 30 : 66,
              height: widget.busy ? 30 : 66,
              decoration: BoxDecoration(
                shape: widget.busy ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: widget.busy ? BorderRadius.circular(10) : null,
                gradient: widget.busy ? null : Palette.grad,
                boxShadow: [
                  BoxShadow(
                    color: Palette.accent.withValues(alpha: 0.45),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: widget.busy
                  ? const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry, required this.onBack});

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: GlassCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Palette.err.withValues(alpha: 0.14),
                ),
                child: const Icon(Icons.videocam_off_rounded, color: Palette.err, size: 26),
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Palette.text, fontSize: 13.5, height: 1.6),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: GhostButton(label: '返回', height: 46, onTap: onBack)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GradientButton(label: '重试', height: 46, onTap: onRetry),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
