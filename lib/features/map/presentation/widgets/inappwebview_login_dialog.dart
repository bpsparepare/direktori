import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class InAppWebViewLoginDialog extends StatefulWidget {
  final Function(
    String cookie,
    String gcToken,
    String csrfToken,
    String userAgent,
    String userName,
  )
  onLoginSuccess;

  const InAppWebViewLoginDialog({super.key, required this.onLoginSuccess});

  @override
  State<InAppWebViewLoginDialog> createState() =>
      _InAppWebViewLoginDialogState();
}

class _InAppWebViewLoginDialogState extends State<InAppWebViewLoginDialog> {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;
  double progress = 0;
  String url = '';
  bool _isChecking = false;

  final String _targetUrl = 'https://matchapro.web.bps.go.id/dirgc';
  final String _loginUrl = 'https://matchapro.web.bps.go.id/login';

  InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: true,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    iframeAllow: "camera; microphone",
    iframeAllowFullscreen: true,
    userAgent:
        "Mozilla/5.0 (Linux; Android 10; SM-G960F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.77 Mobile Safari/537.36",
  );

  @override
  void initState() {
    super.initState();
  }

  Future<void> _checkLoginStatus() async {
    if (_isChecking || webViewController == null) return;
    _isChecking = true;

    try {
      final currentUrl = await webViewController!.getUrl();
      if (currentUrl == null) {
        _isChecking = false;
        return;
      }

      if (currentUrl.toString().contains('matchapro.web.bps.go.id') &&
          !currentUrl.toString().contains('login')) {
        // Kita berada di halaman yang diproteksi, kemungkinan login sukses.
        // Coba extract data.
        await _extractData();
      }
    } catch (e) {
      debugPrint('Error checking login status: $e');
    } finally {
      _isChecking = false;
    }
  }

  Future<void> _extractData() async {
    if (webViewController == null) return;

    // 1. Ambil Cookies (Termasuk HttpOnly)
    final cookieManager = CookieManager.instance();
    final cookies = await cookieManager.getCookies(url: WebUri(_targetUrl));

    // Format cookie string: key=value; key2=value2
    final cookieStr = cookies.map((c) => '${c.name}=${c.value}').join('; ');

    debugPrint('InAppWebView Cookie Found: $cookieStr');

    // 2. Extract Tokens via JS
    // Kita gunakan logic JS yang sama dengan Python
    // PERBAIKAN: Regex untuk gcSubmitToken harus sangat teliti dengan escape characters di Dart string
    final result = await webViewController!.evaluateJavascript(
      source: '''
            (function() {
              let gc_token = '';
              let csrf_token = '';
              let user_name = '';
              
              try {
                  // Try regex first for gcSubmitToken
                  // Pattern: let gcSubmitToken = '...';
                  // Kita cari di seluruh HTML body
                  const html = document.body.innerHTML;
                  
                  // Regex: let\s+gcSubmitToken\s*=\s*(['"])([^'"]+)\1
                  const regex = /let\\s+gcSubmitToken\\s*=\\s*(['"])([^'"]+)\\1/;
                  const match = html.match(regex);
                  if (match) {
                      gc_token = match[2];
                      console.log("Found gc_token via regex: " + gc_token);
                  }
              } catch(e) {
                  console.log("Error regex: " + e);
              }
              
              if (!gc_token) {
                  let el = document.querySelector('input[name="gc_token"]');
                  if (el) {
                      gc_token = el.value;
                      console.log("Found gc_token via input: " + gc_token);
                  }
              }
              
              let meta = document.querySelector('meta[name="csrf-token"]');
              if (meta) csrf_token = meta.content;
              if (!csrf_token) {
                  let el = document.querySelector('input[name="_token"]');
                  if (el) csrf_token = el.value;
              }
              
              // Try getting username
              let userEl = document.querySelector('.dropdown-user .username') || 
                           document.querySelector('.user-panel .info p');
              if (userEl) user_name = userEl.innerText.trim();
              
              return {
                gc_token: gc_token,
                csrf_token: csrf_token,
                user_name: user_name
              };
            })();
          ''',
    );

    if (result != null) {
      final gcToken = result['gc_token'] ?? '';
      final csrfToken = result['csrf_token'] ?? '';
      final userName = result['user_name'] ?? '';

      // Pastikan kita dapat session penting
      final hasSession = cookieStr.contains('laravel_session');
      final hasXsrf = cookieStr.contains('XSRF-TOKEN');

      if (hasSession &&
          hasXsrf &&
          (gcToken.isNotEmpty || csrfToken.isNotEmpty)) {
        // Success!
        if (mounted) {
          widget.onLoginSuccess(
            cookieStr,
            gcToken,
            csrfToken,
            settings.userAgent ?? '',
            userName,
          );
          Navigator.of(context).pop();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login Matchapro (InAppWebView)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => webViewController?.reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (progress < 1.0) LinearProgressIndicator(value: progress),
          Expanded(
            child: InAppWebView(
              key: webViewKey,
              initialUrlRequest: URLRequest(url: WebUri(_targetUrl)),
              initialSettings: settings,
              onWebViewCreated: (controller) {
                webViewController = controller;
              },
              onLoadStart: (controller, url) {
                setState(() {
                  this.url = url.toString();
                });
              },
              onPermissionRequest: (controller, request) async {
                return PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.GRANT,
                );
              },
              onLoadStop: (controller, url) async {
                setState(() {
                  this.url = url.toString();
                });
                // Cek status setiap kali loading selesai
                await _checkLoginStatus();
              },
              onReceivedError: (controller, request, error) {
                // Ignore generic errors
              },
              onProgressChanged: (controller, progress) {
                setState(() {
                  this.progress = progress / 100;
                });
              },
              onConsoleMessage: (controller, consoleMessage) {
                debugPrint('WebConsole: ${consoleMessage.message}');
              },
            ),
          ),
        ],
      ),
    );
  }
}
