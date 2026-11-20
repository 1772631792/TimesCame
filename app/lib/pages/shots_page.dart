import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class ShotsPage extends StatelessWidget {
  const ShotsPage({super.key, required this.app, required this.onOpenCamera});

  final AppState app;
  final VoidCallback onOpenCamera;

  Color _color(Shot s) {
    switch (s.state) {
      case ShotState.done:
        return Palette.ok;
      case ShotState.uploading:
        return Palette.accent;
      case ShotState.failed:
        return Palette.err;
      case ShotState.queued:
        return Palette.warn;
    }
  }

  IconData _icon(Shot s) {
    switch (s.state) {
      case ShotState.done:
        return Icons.cloud_done_rounded;
      case ShotState.uploading:
        return Icons.sync_rounded;
      case ShotState.failed:
        return Icons.error_outline_rounded;
      case ShotState.queued:
        return Icons.schedule_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final shots = app.shots;
        return SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '本次拍摄',
                            style: TextStyle(
                              color: Palette.text,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Pill(label: '${shots.length} 张', dense: true),
                          const Spacer(),
                          if (shots.isNotEmpty)
                            TextButton(
                              onPressed: app.clearSession,
                              style: TextButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                '清空列表',
                                style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.cloud_done_rounded, size: 13, color: Palette.ok),
                          const SizedBox(width: 5),
                          Text(
                            '已同步 ${app.doneCount} 张 · ${app.sentBytesText}',
                            style: const TextStyle(color: Palette.textDim, fontSize: 12),
                          ),
                          if (app.queuedCount > 0) ...[
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: app.uploadAll,
                              child: Text(
                                app.failedCount > 0
                                    ? '重试 ${app.failedCount} 张失败'
                                    : '上传 ${app.queuedCount} 张待传',
                                style: TextStyle(
                                  color: app.failedCount > 0 ? Palette.err : Palette.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              if (shots.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _Empty(onOpenCamera: onOpenCamera),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.82,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _Tile(
                        shot: shots[i],
                        color: _color(shots[i]),
                        icon: _icon(shots[i]),
                        onTap: () => _open(context, shots[i]),
                      ),
                      childCount: shots.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _open(BuildContext context, Shot shot) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (ctx) => _Viewer(app: app, shot: shot, color: _color(shot), icon: _icon(shot)),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.shot,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final Shot shot;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = shot.thumb != null
        ? Image.memory(shot.thumb!, fit: BoxFit.cover, cacheWidth: 320)
        : const Center(child: Icon(Icons.image_rounded, color: Palette.textDim));
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Palette.cardSoft, child: image),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.72)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.5, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Row(
                children: [
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      shot.state == ShotState.uploading
                          ? '${(shot.progress * 100).round()}%'
                          : timeText(shot.at),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (shot.state == ShotState.uploading)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: shot.progress <= 0 ? null : shot.progress,
                  minHeight: 2.5,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onOpenCamera});

  final VoidCallback onOpenCamera;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Palette.accent.withValues(alpha: 0.18),
                    Palette.accent2.withValues(alpha: 0.12),
                  ],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Icon(Icons.photo_camera_back_rounded, color: Palette.accent, size: 36),
            ),
            const SizedBox(height: 18),
            const Text(
              '还没有照片',
              style: TextStyle(color: Palette.text, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              '拍一张，电脑上的文件夹里会立刻出现',
              textAlign: TextAlign.center,
              style: TextStyle(color: Palette.textDim, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 180,
              child: GradientButton(
                label: '去拍照',
                icon: Icons.camera_alt_rounded,
                height: 48,
                onTap: onOpenCamera,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Viewer extends StatelessWidget {
  const _Viewer({
    required this.app,
    required this.shot,
    required this.color,
    required this.icon,
  });

  final AppState app;
  final Shot shot;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final source = shot.data ?? shot.thumb;
    final status = switch (shot.state) {
      ShotState.done => '已同步到电脑 · ${shot.ms ?? 0} ms',
      ShotState.uploading => '同步中 ${(shot.progress * 100).round()}%',
      ShotState.failed => shot.error ?? '上传失败',
      ShotState.queued => '等待上传',
    };
    return Dialog(
      insetPadding: const EdgeInsets.all(14),
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (source != null)
                  InteractiveViewer(
                    maxScale: 4,
                    child: Image.memory(source, fit: BoxFit.contain),
                  ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: GlassIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.pop(context),
                    size: 40,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  shot.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Palette.text, fontSize: 12.5),
                ),
                const SizedBox(height: 4),
                Text(
                  '${shot.sizeText} · ${timeText(shot.at)}',
                  style: const TextStyle(color: Palette.textDim, fontSize: 11.5),
                ),
                if (shot.state == ShotState.failed) ...[
                  const SizedBox(height: 14),
                  GradientButton(label: '重新上传', icon: Icons.refresh_rounded, height: 46, onTap: () => app.retry(shot)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
