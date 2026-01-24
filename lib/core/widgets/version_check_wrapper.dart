import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/version_check_service.dart';
import '../utils/browser_utils.dart';

class VersionCheckWrapper extends StatefulWidget {
  final Widget child;
  const VersionCheckWrapper({super.key, required this.child});

  @override
  State<VersionCheckWrapper> createState() => _VersionCheckWrapperState();
}

class _VersionCheckWrapperState extends State<VersionCheckWrapper>
    with WidgetsBindingObserver {
  final _service = VersionCheckService();
  bool _isDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Delay sedikit agar tidak menabrak splash screen/mounting awal
    Future.delayed(const Duration(seconds: 2), _checkForUpdate);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForUpdate();
    }
  }

  Future<void> _checkForUpdate() async {
    if (_isDialogShown) return;

    final info = await _service.checkUpdate();
    if (info != null && info.hasUpdate && mounted) {
      _showUpdateDialog(info);
    }
  }

  void _showUpdateDialog(UpdateInfo info) {
    setState(() {
      _isDialogShown = true;
    });

    showDialog(
      context: context,
      barrierDismissible:
          !info.forceUpdate, // Jika mandatory, tidak bisa di-dismiss
      builder: (context) => PopScope(
        canPop: !info.forceUpdate, // Prevent back button if mandatory
        child: AlertDialog(
          title: const Text('Pembaruan Tersedia'),
          content: Text(
            'Versi baru ${info.latestVersion} telah tersedia.\n'
            '${info.forceUpdate ? "Anda harus memperbarui aplikasi untuk melanjutkan." : "Apakah Anda ingin memperbarui sekarang?"}',
          ),
          actions: [
            if (!info.forceUpdate)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _isDialogShown = false; // Allow re-check later
                  });
                },
                child: const Text('Nanti Saja'),
              ),
            FilledButton(
              onPressed: () async {
                if (kIsWeb) {
                  BrowserUtils.reload();
                } else {
                  if (info.downloadUrl != null) {
                    final uri = Uri.parse(info.downloadUrl!);
                    try {
                      // Coba buka di aplikasi eksternal (Browser/Google Drive App)
                      if (!await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      )) {
                        throw 'Could not launch $uri';
                      }
                    } catch (e) {
                      debugPrint(
                        'Gagal membuka external, mencoba mode in-app: $e',
                      );
                      try {
                        // Fallback: Coba buka dengan mode default (bisa WebView)
                        if (!await launchUrl(
                          uri,
                          mode: LaunchMode.platformDefault,
                        )) {
                          throw 'Could not launch fallback $uri';
                        }
                      } catch (e2) {
                        debugPrint('Gagal membuka link update: $e2');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Gagal membuka link. Link disalin ke clipboard.',
                              ),
                              action: SnackBarAction(
                                label: 'Salin Manual',
                                onPressed: () {
                                  // Clipboard handling
                                },
                              ),
                            ),
                          );
                          // Salin ke clipboard otomatis
                          await Clipboard.setData(
                            ClipboardData(text: info.downloadUrl!),
                          );
                        }
                      }
                    }
                  }
                }
              },
              child: Text(kIsWeb ? 'Refresh Sekarang' : 'Update Sekarang'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
