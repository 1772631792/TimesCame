import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'net_client.dart';
import 'pages/camera_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_sheet.dart';
import 'pages/shots_page.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final app = AppState(NetClient());
  await app.load();
  unawaited(app.net.startDiscovery());
  runApp(TimesCamApp(app: app));
}

class TimesCamApp extends StatelessWidget {
  const TimesCamApp({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TimesCam',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Shell(app: app),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.app});

  final AppState app;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  bool _cameraBuilt = false;

  AppState get app => widget.app;

  void _go(int index) {
    if (index == 1) _cameraBuilt = true;
    setState(() => _tab = index);
  }

  @override
  Widget build(BuildContext context) {
    // 相机页 / 相册页时拦下系统返回手势，先回首页，而不是直接退出 App
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _go(0);
      },
      child: Scaffold(
        extendBody: true,
        backgroundColor: Palette.bg,
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: kBgGradient),
          child: Stack(
            children: [
              const Positioned(top: -140, left: -90, child: _Glow(color: Palette.accent, size: 340)),
              const Positioned(top: 90, right: -120, child: _Glow(color: Palette.accent2, size: 340)),
              IndexedStack(
                index: _tab,
                children: [
                  HomePage(
                    app: app,
                    onOpenCamera: () => _go(1),
                    onOpenSettings: () => showSettings(context, app),
                  ),
                  _cameraBuilt
                      ? CameraPage(
                          app: app,
                          active: _tab == 1,
                          onBack: () => _go(0),
                          onOpenShots: () => _go(2),
                        )
                      : const SizedBox.shrink(),
                  ShotsPage(app: app, onOpenCamera: () => _go(1)),
                ],
              ),
            ],
          ),
        ),
        bottomNavigationBar: _tab == 1
            ? null
            : AnimatedBuilder(
                animation: app,
                builder: (context, _) => _NavBar(
                  index: _tab,
                  onTap: _go,
                  connected: app.net.state == LinkState.connected,
                  shopBadge: app.shots.length,
                ),
              ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0.0)],
          ),
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.index,
    required this.onTap,
    required this.connected,
    required this.shopBadge,
  });

  final int index;
  final ValueChanged<int> onTap;
  final bool connected;
  final int shopBadge;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: bottom > 0 ? bottom : 14),
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              color: const Color(0xFF0A111C).withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                _NavItem(
                  label: '连接',
                  icon: Icons.wifi_tethering_rounded,
                  selected: index == 0,
                  dot: connected ? Palette.ok : Palette.warn,
                  onTap: () => onTap(0),
                ),
                _NavItem(
                  label: '相机',
                  icon: Icons.camera_alt_rounded,
                  selected: index == 1,
                  onTap: () => onTap(1),
                  highlight: true,
                ),
                _NavItem(
                  label: '相册',
                  icon: Icons.photo_library_rounded,
                  selected: index == 2,
                  badge: shopBadge > 0 ? '$shopBadge' : null,
                  onTap: () => onTap(2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.dot,
    this.badge,
    this.highlight = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;
  final String? badge;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Palette.text : Palette.textDim;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                gradient: selected
                    ? LinearGradient(
                        colors: highlight
                            ? [Palette.accent.withValues(alpha: 0.24), Palette.accent2.withValues(alpha: 0.2)]
                            : [
                                Colors.white.withValues(alpha: 0.08),
                                Colors.white.withValues(alpha: 0.04),
                              ],
                      )
                    : null,
                borderRadius: BorderRadius.circular(16),
                border: selected
                    ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                    : null,
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 21, color: highlight && selected ? Palette.accent : color),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (dot != null)
              Positioned(
                top: 14,
                right: 40,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
                ),
              ),
            if (badge != null)
              Positioned(
                top: 12,
                right: 34,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Palette.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
