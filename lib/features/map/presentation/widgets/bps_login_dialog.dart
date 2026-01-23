import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
// Import for macOS support
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:webview_cookie_manager/webview_cookie_manager.dart';

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
  final WebViewController? controller;

  const BpsLoginDialog({
    super.key,
    required this.onLoginSuccess,
    this.controller,
  });

  @override
  State<BpsLoginDialog> createState() => _BpsLoginDialogState();
}

class _BpsLoginDialogState extends State<BpsLoginDialog> {
  late final WebViewController _controller;
  bool _isInitialized = false;
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initWebview();
  }

  Future<void> _initWebview() async {
    // Jika controller sudah diberikan dari luar (BpsGcService), gunakan itu.
    if (widget.controller != null) {
      _controller = widget.controller!;
      _controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _status = 'Loading: $url';
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _status = 'Please Login...';
              });
            }
            _checkPageContent();
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('Web resource error: ${error.description}');
          },
        ),
      );

      await _controller.loadRequest(
        Uri.parse('https://matchapro.web.bps.go.id/dirgc'),
      );

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
      return;
    }

    try {
      // Platform-specific params
      late final PlatformWebViewControllerCreationParams params;
      if (WebViewPlatform.instance is WebKitWebViewPlatform) {
        params = WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
          mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
        );
      } else {
        params = const PlatformWebViewControllerCreationParams();
      }

      final WebViewController controller =
          WebViewController.fromPlatformCreationParams(params);

      controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(_spoofedUA)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              if (mounted) {
                setState(() {
                  _status = 'Loading: $url';
                });
              }
            },
            onPageFinished: (String url) {
              if (mounted) {
                setState(() {
                  _status = 'Please Login...';
                });
              }
              _checkPageContent();
            },
            onWebResourceError: (WebResourceError error) {
              debugPrint('Web resource error: ${error.description}');
            },
          ),
        );

      // Add script to override navigator properties if possible
      // Note: addJavaScriptChannel is for communication, not injection at start.
      // webview_flutter 4.x doesn't have addScriptToExecuteOnDocumentCreated easily accessible across all platforms in the same way,
      // but we can try running it after load or using platform specific features if needed.
      // For now, we'll rely on UA and run script after page load if needed.

      if (controller.platform is WebKitWebViewController) {
        (controller.platform as WebKitWebViewController)
            .setAllowsBackForwardNavigationGestures(true);
      }

      _controller = controller;
      await _controller.loadRequest(
        Uri.parse('https://matchapro.web.bps.go.id/dirgc'),
      );

      if (mounted) {
        setState(() {
          _isInitialized = true;
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
          ? WebViewWidget(controller: _controller)
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

      final result = await _controller.runJavaScriptReturningResult(script);

      String jsonString = '';
      if (result is String) {
        // webview_flutter might return the JSON string wrapped in quotes, e.g. "{\"cookie\":...}"
        // We need to unquote it if it's double encoded.
        // However, usually it returns the result of evaluation.
        // If it's a JSON string, it might be literally just the string.
        // Let's check if it starts and ends with quotes
        jsonString = result;
        if (jsonString.startsWith('"') && jsonString.endsWith('"')) {
          jsonString = jsonDecode(jsonString); // Unescape the string
        }
      }

      // Hapus logika pengambilan cookie via Manager yang error
      // Kita akan mengandalkan Cookie Global WebView (Android/iOS)
      // dan pengiriman data via WebView Injection, bukan http.Client Dart.

      String managerCookieHeader = '';
      try {
        final cookieManager = WebviewCookieManager();
        final gotCookies = await cookieManager.getCookies(
          'https://matchapro.web.bps.go.id/dirgc',
        );
        if (gotCookies.isNotEmpty) {
          managerCookieHeader = gotCookies
              .map((c) => '${c.name}=${c.value}')
              .join('; ');
          debugPrint(
            'proses kirim: Cookie Manager Found ${gotCookies.length} cookies',
          );
          for (var c in gotCookies) {
            debugPrint(' - ${c.name}: ${c.value} (HttpOnly: ${c.httpOnly})');
          }
        }
      } catch (e) {
        debugPrint('proses kirim: Gagal ambil cookie via Manager: $e');
      }

      if (jsonString.isNotEmpty) {
        if (mounted) {
          setState(() {
            _status = 'Login Terdeteksi. Mengambil Sesi...';
          });
        }
        final map = jsonDecode(jsonString);
        // ignore: unused_local_variable
        final jsCookie = map['cookie']?.toString() ?? '';
        final gc = map['gc_token']?.toString() ?? '';
        final csrf = map['csrf_token']?.toString() ?? '';
        final uaFromJs = map['ua']?.toString() ?? '';
        final name = map['user_name']?.toString() ?? '';
        debugPrint('proses kirim: Login JS Cookie: $jsCookie');
        debugPrint('proses kirim: Login JS gc_token: $gc');
        debugPrint('proses kirim: Login JS csrf_token: $csrf');
        debugPrint('proses kirim: Login JS user: $name');

        // Gunakan cookie dari CookieManager karena lebih lengkap (ada HttpOnly)
        // Gabungkan jika perlu, tapi biasanya CookieManager sudah mencakup semua yang penting.
        final finalCookie = managerCookieHeader.isNotEmpty
            ? managerCookieHeader
            : jsCookie;

        // If JS returns the default UA (because setUserAgent failed or delayed), use our spoofed one
        final finalUA = uaFromJs.contains('Android') ? uaFromJs : _spoofedUA;

        if (gc.isNotEmpty && csrf.isNotEmpty) {
          widget.onLoginSuccess(finalCookie, gc, csrf, finalUA, name);
          if (mounted) Navigator.pop(context);
        } else {
          debugPrint('proses kirim: Login JS token belum ditemukan.');
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }
}
