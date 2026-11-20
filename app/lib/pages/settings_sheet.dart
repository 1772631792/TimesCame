import 'package:flutter/material.dart';

import '../app_state.dart';
import '../net_client.dart';
import '../theme.dart';
import '../widgets.dart';

Future<void> showSettings(BuildContext context, AppState app) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _SettingsSheet(app: app),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.app});

  final AppState app;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final TextEditingController _host =
      TextEditingController(text: widget.app.settings.manualHost);
  late final TextEditingController _name =
      TextEditingController(text: widget.app.settings.deviceName);
  bool _connecting = false;

  AppState get app => widget.app;

  @override
  void dispose() {
    _host.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    await app.net.connectManual(_host.text);
    if (mounted) setState(() => _connecting = false);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final s = app.settings;
        return Container(
          margin: const EdgeInsets.only(top: 60),
          padding: EdgeInsets.fromLTRB(20, 12, 20, 26 + bottom),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF121B2B), Color(0xFF080C14)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: Color(0x22FFFFFF))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    '设置',
                    style: TextStyle(color: Palette.text, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  GlassIconButton(
                    icon: Icons.close_rounded,
                    size: 36,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Column(
                          children: [
                            _SwitchRow(
                              icon: Icons.auto_mode_rounded,
                              title: '拍完自动上传',
                              subtitle: '关闭后只存在手机里，可在相册页手动补传',
                              value: s.autoSync,
                              onChanged: (v) {
                                s.autoSync = v;
                                app.saveSettings();
                                setState(() {});
                              },
                            ),
                            const _Divider(),
                            _SwitchRow(
                              icon: Icons.sd_card_rounded,
                              title: '保留手机副本',
                              subtitle: '上传成功后不删除相机缓存',
                              value: s.keepLocal,
                              onChanged: (v) {
                                s.keepLocal = v;
                                app.saveSettings();
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.high_quality_rounded, size: 16, color: Palette.accent2),
                                SizedBox(width: 8),
                                Text(
                                  '照片画质',
                                  style: TextStyle(
                                    color: Palette.text,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (var i = 0; i < Settings.resolutionLabels.length; i++)
                                  _Choice(
                                    label: Settings.resolutionLabels[i],
                                    selected: s.resolution == i,
                                    onTap: () {
                                      s.resolution = i;
                                      app.saveSettings();
                                      setState(() {});
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              '画质越高上传越慢；1 张 4K 照片约 2~4 MB，WiFi 下通常 0.3~0.8 秒。',
                              style: TextStyle(color: Palette.textDim, fontSize: 11.5, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ConnState(app: app),
                            if (s.hostName.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.bookmark_added_rounded,
                                      size: 14, color: Palette.ok),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '记住的电脑：${s.hostName}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Palette.textDim, fontSize: 11.5),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      app.forgetHost();
                                      setState(() {});
                                    },
                                    child: const Text(
                                      '忘记',
                                      style: TextStyle(color: Palette.err, fontSize: 11.5),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            TextField(
                              controller: _host,
                              keyboardType: TextInputType.url,
                              style: const TextStyle(color: Palette.text, fontSize: 13.5),
                              decoration: _decoration('电脑地址，如 192.168.1.8:37021'),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: GhostButton(
                                    label: '重新搜索',
                                    icon: Icons.refresh_rounded,
                                    height: 44,
                                    onTap: () => app.net.startDiscovery(),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: GradientButton(
                                    label: _connecting ? '连接中…' : '手动连接',
                                    height: 44,
                                    enabled: !_connecting,
                                    onTap: _connect,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.badge_rounded, size: 16, color: Palette.accent),
                                SizedBox(width: 8),
                                Text(
                                  '设备名字（显示在电脑上）',
                                  style: TextStyle(
                                    color: Palette.text,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _name,
                              style: const TextStyle(color: Palette.text, fontSize: 13.5),
                              onSubmitted: (v) {
                                app.settings.deviceName = v.trim().isEmpty ? '我的手机' : v.trim();
                                app.saveSettings();
                              },
                              decoration: _decoration('我的手机'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'TimesCam 2.0.0 · 局域网直传协议 v1\n'
                        '多台电脑时首页会列出头像，点一下就连那台\n'
                        '照片只在你自己的 WiFi 内传输，不经过任何服务器。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Palette.textDim, fontSize: 11, height: 1.7),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF56637A), fontSize: 13),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    );
  }
}

class _ConnState extends StatelessWidget {
  const _ConnState({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final net = app.net;
    final connected = net.state == LinkState.connected;
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: connected ? Palette.ok : Palette.warn,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            connected
                ? '已连接 ${net.host?.label ?? ''}（${net.latency} ms）'
                : net.hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Palette.textDim, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 17, color: Palette.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Palette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: Palette.textDim, fontSize: 11.5, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: Colors.white.withValues(alpha: 0.05));
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          gradient: selected ? Palette.grad : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected ? Colors.transparent : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Palette.textDim,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
