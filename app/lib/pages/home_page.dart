import 'package:flutter/material.dart';

import '../app_state.dart';
import '../net_client.dart';
import '../theme.dart';
import '../widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.app,
    required this.onOpenCamera,
    required this.onOpenSettings,
  });

  final AppState app;
  final VoidCallback onOpenCamera;
  final VoidCallback onOpenSettings;

  Future<void> _manualConnect(BuildContext context) async {
    final controller = TextEditingController(text: app.settings.manualHost);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.card,
        title: const Text('手动连接电脑', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '电脑端窗口左上角会显示地址，例如 192.168.1.8:37021。',
              style: TextStyle(color: Palette.textDim, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              style: const TextStyle(color: Palette.text, fontSize: 15),
              decoration: InputDecoration(
                hintText: '192.168.1.8:37021',
                hintStyle: const TextStyle(color: Color(0xFF56637A)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Palette.textDim)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('连接'),
          ),
        ],
      ),
    );
    if (ok == true) {
      app.settings.manualHost = controller.text.trim();
      await app.saveSettings();
      await app.net.connectManual(controller.text);
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final net = app.net;
        final connected = net.state == LinkState.connected;
        return SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(onOpenSettings: onOpenSettings),
                const SizedBox(height: 18),
                Center(
                  child: RadarOrb(
                    active: net.state != LinkState.connected,
                    connected: connected,
                    size: 208,
                  ),
                ),
                const SizedBox(height: 10),
                _StatusBlock(app: app),
                const SizedBox(height: 20),
                if (connected)
                  _HostCard(app: app, onRescan: () => net.startDiscovery())
                else
                  _FinderCard(
                    app: app,
                    onRescan: () => net.startDiscovery(),
                    onManual: () => _manualConnect(context),
                  ),
                const SizedBox(height: 16),
                GradientButton(
                  label: connected ? '开始拍摄' : '先拍，连上后自动补传',
                  icon: Icons.camera_alt_rounded,
                  height: 58,
                  onTap: onOpenCamera,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: StatTile(label: '已同步', value: '${app.sentCount} 张')),
                    const SizedBox(width: 10),
                    Expanded(child: StatTile(label: '总流量', value: app.sentBytesText)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatTile(
                        label: '平均耗时',
                        value: app.avgMs == 0 ? '—' : '${app.avgMs} ms',
                        color: app.avgMs > 0 && app.avgMs < 800 ? Palette.ok : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _Steps(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: Palette.grad,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: Palette.accent.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.camera_rounded, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TimesCam',
              style: TextStyle(
                color: Palette.text,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(height: 2),
            Text(
              '同网快传 · 拍完就到电脑',
              style: TextStyle(color: Palette.textDim, fontSize: 12),
            ),
          ],
        ),
        const Spacer(),
        GlassIconButton(
          icon: Icons.tune_rounded,
          onTap: onOpenSettings,
        ),
      ],
    );
  }
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final net = app.net;
    final connected = net.state == LinkState.connected;
    final scanning = net.state == LinkState.scanning;

    final title = connected
        ? (net.host?.name ?? '电脑')
        : scanning
            ? '正在寻找电脑…'
            : '暂未连接';

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: connected ? Palette.ok : (scanning ? Palette.warn : Palette.err),
                boxShadow: [
                  BoxShadow(
                    color: (connected ? Palette.ok : Palette.warn).withValues(alpha: 0.6),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Palette.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          net.hint,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Palette.textDim, fontSize: 13, height: 1.5),
        ),
        if (connected) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Pill(
                label: net.latency == 0 ? '链路已就绪' : '${net.latency} ms',
                icon: Icons.bolt_rounded,
                color: Palette.ok,
                dense: true,
              ),
              const SizedBox(width: 8),
              Pill(
                label: net.host?.label ?? '',
                icon: Icons.lan_rounded,
                color: Palette.accent,
                dense: true,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _HostCard extends StatelessWidget {
  const _HostCard({required this.app, required this.onRescan});

  final AppState app;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final host = app.net.host;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_rounded, size: 17, color: Palette.accent),
              const SizedBox(width: 8),
              const Text(
                '照片保存位置（电脑）',
                style: TextStyle(color: Palette.textDim, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                onPressed: onRescan,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('重新搜索', style: TextStyle(color: Palette.accent, fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            (host?.dir.isNotEmpty ?? false) ? host!.dir : '电脑端默认目录',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Palette.text,
              fontSize: 13.5,
              height: 1.45,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Palette.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 16, color: Palette.ok),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '拍完自动同步，电脑端立即出现',
                    style: TextStyle(color: Palette.text.withValues(alpha: 0.85), fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FinderCard extends StatelessWidget {
  const _FinderCard({
    required this.app,
    required this.onRescan,
    required this.onManual,
  });

  final AppState app;
  final VoidCallback onRescan;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wifi_tethering_rounded, size: 17, color: Palette.accent2),
              const SizedBox(width: 8),
              const Text(
                '同一 WiFi 自动发现',
                style: TextStyle(color: Palette.text, fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Pill(label: 'UDP ${37020}', color: Palette.textDim, dense: true),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '手机和电脑连同一个 WiFi，电脑端运行 timescam_host.py，通常 1 秒内就能连上。',
            style: TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.6),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: '重新搜索',
                  icon: Icons.refresh_rounded,
                  height: 44,
                  onTap: onRescan,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GhostButton(
                  label: '手动连接',
                  icon: Icons.keyboard_rounded,
                  height: 44,
                  onTap: onManual,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    const items = <(int, String, String)>[
      (1, '电脑端运行上机位', '双击 host 目录下的 start_host.bat'),
      (2, '手机连同一个 WiFi', '电脑显示的地址就是本机 IP'),
      (3, '拍照即同步', '拍一张，电脑文件夹里马上就有'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('怎么用'),
        const SizedBox(height: 10),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                  ),
                  child: Text(
                    '${item.$1}',
                    style: const TextStyle(
                      color: Palette.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  item.$2,
                  style: const TextStyle(color: Palette.text, fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.$3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Palette.textDim, fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
