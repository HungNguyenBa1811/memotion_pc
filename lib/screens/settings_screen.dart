import 'package:flutter/material.dart';
import 'package:flutter_lite_camera/flutter_lite_camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/settings_model.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _httpCtrl;
  late final TextEditingController _wsCtrl;

  List<String> _cameras = []; // device name strings from FlutterLiteCamera
  bool _loadingCameras = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _httpCtrl = TextEditingController(text: settings.backendBaseUrl);
    _wsCtrl   = TextEditingController(text: settings.backendWsBase);
    _loadCameras();
  }

  @override
  void dispose() {
    _httpCtrl.dispose();
    _wsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCameras() async {
    try {
      final cams = await FlutterLiteCamera().getDeviceList();
      if (mounted) setState(() { _cameras = cams; _loadingCameras = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingCameras = false);
    }
  }

  Future<void> _save() async {
    final http = _httpCtrl.text.trim();
    final ws   = _wsCtrl.text.trim();

    if (http.isEmpty || ws.isEmpty) {
      _showSnack('URL không được để trống', isError: true);
      return;
    }
    if (!http.startsWith('http')) {
      _showSnack('HTTP URL phải bắt đầu bằng http:// hoặc https://', isError: true);
      return;
    }
    if (!ws.startsWith('ws')) {
      _showSnack('WS URL phải bắt đầu bằng ws:// hoặc wss://', isError: true);
      return;
    }

    setState(() => _saving = true);
    final current = ref.read(settingsProvider);
    await ref.read(settingsProvider.notifier).update(
          current.copyWith(backendBaseUrl: http, backendWsBase: ws),
        );
    if (mounted) {
      setState(() => _saving = false);
      _showSnack('Đã lưu cài đặt');
    }
  }

  Future<void> _reset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        title: const Text('Khôi phục mặc định?'),
        content: const Text('Tất cả cài đặt sẽ về giá trị ban đầu.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Khôi phục')),
        ],
      ),
    );
    if (confirm != true) return;

    await ref.read(settingsProvider.notifier).reset();
    final defaults = AppSettings.defaults;
    _httpCtrl.text = defaults.backendBaseUrl;
    _wsCtrl.text   = defaults.backendWsBase;
    if (mounted) _showSnack('Đã khôi phục mặc định');
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.error : AppTheme.primary,
      behavior: SnackBarBehavior.floating,
      width: 360,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceContainer,
        title: const Text('Cài đặt'),
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        actions: [
          TextButton(
            onPressed: _reset,
            child: const Text('Khôi phục mặc định',
                style: TextStyle(color: AppTheme.onSurfaceMuted)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Backend ──────────────────────────────────────────────
                const _SectionHeader(title: 'Backend', icon: Icons.cloud_outlined),
                const SizedBox(height: 16),
                _UrlField(
                  controller: _httpCtrl,
                  label: 'HTTP Base URL',
                  hint: AppConstants.defaultBackendHttp,
                  prefix: 'http(s)://',
                ),
                const SizedBox(height: 14),
                _UrlField(
                  controller: _wsCtrl,
                  label: 'WebSocket Base URL',
                  hint: AppConstants.defaultBackendWs,
                  prefix: 'ws(s)://',
                ),

                const SizedBox(height: 40),

                // ── Camera ───────────────────────────────────────────────
                const _SectionHeader(title: 'Camera', icon: Icons.videocam_outlined),
                const SizedBox(height: 16),
                _loadingCameras
                    ? const Center(child: CircularProgressIndicator())
                    : _cameras.isEmpty
                        ? const Text('Không tìm thấy camera',
                            style: TextStyle(color: AppTheme.onSurfaceMuted))
                        : _CameraSelector(
                            cameras: _cameras,
                            selectedIndex: settings.cameraIndex,
                            onChanged: (idx) async {
                              await ref
                                  .read(settingsProvider.notifier)
                                  .update(settings.copyWith(cameraIndex: idx));
                            },
                          ),

                const SizedBox(height: 48),

                // ── Save button ──────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Đang lưu...' : 'Lưu cài đặt'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.onSurface)),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: Colors.white12)),
      ],
    );
  }
}

class _UrlField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final String prefix;

  const _UrlField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppTheme.onSurfaceMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
            prefixText: prefix,
            prefixStyle: const TextStyle(
                color: AppTheme.primary, fontSize: 13),
            filled: true,
            fillColor: AppTheme.surfaceContainer,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }
}

class _CameraSelector extends StatelessWidget {
  final List<String> cameras; // device name strings
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _CameraSelector({
    required this.cameras,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(cameras.length, (i) {
        final name = cameras[i];
        final selected = i == selectedIndex;
        return InkWell(
          onTap: () => onChanged(i),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.12)
                  : AppTheme.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? AppTheme.primary.withValues(alpha: 0.6)
                    : Colors.white12,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.videocam_outlined,
                  size: 18,
                  color: selected
                      ? AppTheme.primary
                      : AppTheme.onSurfaceMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name.isNotEmpty ? name : 'Camera $i',
                    style: TextStyle(
                      color: selected
                          ? AppTheme.onSurface
                          : AppTheme.onSurfaceMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle,
                      size: 18, color: AppTheme.primary),
              ],
            ),
          ),
        );
      }),
    );
  }
}
