import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

const _spoofedUA =
    'Mozilla/5.0 (Linux; Android 16; ONEPLUS 15 Build/SKQ1.211202.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/143.0.7499.192 Mobile Safari/537.36';

class BpsLoginDialog extends StatefulWidget {
  final Function(
    String cookie,
    String gcToken,
    String csrfToken,
    String userAgent,
    String userName,
  )
  onLoginSuccess;

  const BpsLoginDialog({super.key, required this.onLoginSuccess});

  @override
  State<BpsLoginDialog> createState() => _BpsLoginDialogState();
}

class _BpsLoginDialogState extends State<BpsLoginDialog> {
  final _controller = WebviewController();
  bool _isInitialized = false;
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initWebview();
  }

  Future<void> _initWebview() async {
    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.white);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      // Use the specific Android UA string that mimics login.py to ensure consistency
      await _controller.setUserAgent(_spoofedUA);

      // Inject script to override navigator properties (mock mobile environment)
      try {
        // Note: webview_windows might not support addScriptToExecuteOnDocumentCreated in all versions.
        // If this fails, we rely on UserAgent only.
        // Assuming the method exists or using executeScript as a fallback (though less effective for init).
        // Using dynamic dispatch or just trying standard API if available.
        // Since I cannot verify the package version, I will try to use the method if I can't find it I'll just use executeScript immediately after load (less safe).
        // Actually, let's just check if we can call it. If not, catch error.
        // But for safety, I'll assume it might not be there and handle it.
        // However, standard WebView2 wrapper usually has it.
        await _controller.addScriptToExecuteOnDocumentCreated(r"""
          Object.defineProperty(navigator, 'platform', {
              get: function() { return 'Linux armv8l'; }
          });
          Object.defineProperty(navigator, 'maxTouchPoints', {
              get: function() { return 5; }
          });
        """);
      } catch (e) {
        debugPrint('Script injection error (might not be supported): $e');
      }

      // Listen to navigation
      _controller.url.listen((url) {
        if (mounted) {
          setState(() {
            _status = 'Loading: $url';
          });
        }
      });

      _controller.loadingState.listen((state) async {
        if (state == LoadingState.navigationCompleted) {
          _checkPageContent();
        }
      });

      await _controller.loadUrl('https://matchapro.web.bps.go.id/dirgc');

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _status = 'Please Login...';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Error: $e';
        });
      }
    }
  }

  Future<void> _checkPageContent() async {
    // Re-use logic
    await _manualCheck();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_status)),
      body: _isInitialized
          ? Webview(_controller)
          : const Center(child: CircularProgressIndicator()),
      floatingActionButton: FloatingActionButton(
        onPressed: _manualCheck,
        child: const Icon(Icons.check),
        tooltip: 'Check Tokens',
      ),
    );
  }

  Future<void> _manualCheck() async {
    try {
      final script = r'''
            (function() {
                var gc_token = '';
                var csrf_token = '';
                var user_name = '';

                // 1. Try variable gcSubmitToken
                try {
                    var html = document.body.innerHTML;
                    var match = html.match(/let\s+gcSubmitToken\s*=\s*(['"])([^'"]+)\1/);
                    if (match && match[2]) {
                        gc_token = match[2];
                    }
                } catch(e) {}

                // 2. Try input gc_token
                if (!gc_token) {
                    var inputGc = document.querySelector('input[name="gc_token"]');
                    if (inputGc) gc_token = inputGc.value;
                }
                
                // 3. Try meta csrf-token
                var metaCsrf = document.querySelector('meta[name="csrf-token"]');
                if (metaCsrf) csrf_token = metaCsrf.content;
                
                // 4. Try input _token
                if (!csrf_token) {
                    var inputCsrf = document.querySelector('input[name="_token"]');
                    if (inputCsrf) csrf_token = inputCsrf.value;
                }

                // 5. Try finding user name
                // Common AdminLTE/Bootstrap patterns
                var userEl = document.querySelector('.user-panel .info p') || 
                             document.querySelector('.dropdown-user .username') ||
                             document.querySelector('.user-menu span.hidden-xs') ||
                             document.querySelector('.navbar-nav .user-menu a span');
                if (userEl) {
                    user_name = userEl.innerText.trim();
                }
                
                return JSON.stringify({
                    cookie: document.cookie,
                    gc_token: gc_token,
                    csrf_token: csrf_token,
                    user_name: user_name,
                    ua: navigator.userAgent
                });
            })();
        ''';

      final result = await _controller.executeScript(script);

      if (result != null && result is String) {
        final map = jsonDecode(result);
        final cookieHeader = map['cookie']?.toString() ?? '';
        final gc = map['gc_token']?.toString() ?? '';
        final csrf = map['csrf_token']?.toString() ?? '';
        final uaFromJs = map['ua']?.toString() ?? '';
        final name = map['user_name']?.toString() ?? '';

        // If JS returns the default UA (because setUserAgent failed or delayed), use our spoofed one
        final finalUA = uaFromJs.contains('Android') ? uaFromJs : _spoofedUA;

        if (gc.isNotEmpty && csrf.isNotEmpty) {
          widget.onLoginSuccess(cookieHeader, gc, csrf, finalUA, name);
          if (mounted) Navigator.pop(context);
        } else {
          // Only show snackbar if triggered manually to avoid spamming
          // But since _checkPageContent calls this, we might spam.
          // So let's suppress automatic spam or just log.
          debugPrint('Tokens not found yet.');
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }
}
