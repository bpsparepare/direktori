import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class BpsGcService {
  final String baseUrl = 'https://matchapro.web.bps.go.id';

  final http.Client _client;

  // Headless WebView untuk background task
  HeadlessInAppWebView? _headlessWebView;
  final Completer<void> _initCompleter = Completer<void>();
  bool _isWebViewInitialized = false;

  String? _csrfToken;
  String? _gcToken;
  String? _cookieHeader;
  String _userAgent =
      'Mozilla/5.0 (Linux; Android 16; ONEPLUS 15 Build/SKQ1.211202.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/143.0.7499.192 Mobile Safari/537.36';

  final List<String> _availableUserAgents = [
    "Mozilla/5.0 (Linux; Android 16; ONEPLUS 15 Build/SKQ1.211202.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/143.0.7499.192 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 15; SM-S928B Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/133.0.6943.88 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 14; Pixel 8a Build/UP1A.231005.007; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/130.0.6723.102 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 15; POCO X7 Pro Build/UKQ1.231003.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/133.0.6943.45 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 16; SM-A556E Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/134.0.6998.88 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 14; ONEPLUS PJZ110 Build/SKQ1.210216.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/132.0.6834.102 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 15; Redmi Note 14 Pro Build/UKQ1.231003.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/133.0.6943.127 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 16; Pixel 9 Pro Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/134.0.6998.45 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 14; moto g85 5G Build/S3SGS32.12-78-7; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.6778.200 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 15; SM-G991B Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/132.0.6834.88 Mobile Safari/537.36",
  ];

  BpsGcService({http.Client? client}) : _client = client ?? http.Client();

  void _rotateUserAgent() {
    _userAgent = (_availableUserAgents..shuffle()).first;
    debugPrint('proses kirim: Rotated User-Agent to $_userAgent');
  }

  Future<void> _disposeWebView() async {
    if (_headlessWebView != null) {
      try {
        await _headlessWebView?.dispose();
      } catch (e) {
        debugPrint('proses kirim: Error disposing WebView: $e');
      }
      _headlessWebView = null;
      _isWebViewInitialized = false;
      // Reset completer agar init berikutnya bisa berjalan
      if (_initCompleter.isCompleted) {
        // Kita tidak bisa me-reset completer yang sudah complete, jadi kita biarkan.
        // Tapi kita perlu flag baru atau cara baru handling init status.
        // Untuk sederhananya, kita anggap initCompleter hanya untuk first init.
        // Tapi jika kita dispose, kita harus bisa re-init.
        // Sebaiknya kita tidak mengandalkan _initCompleter untuk re-init.
      }
    }
  }

  Future<void> _initWebView({bool forceRecreate = false}) async {
    if (forceRecreate) {
      await _disposeWebView();
    }

    if (_isWebViewInitialized && _headlessWebView != null) return;

    try {
      _headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri('$baseUrl/dirgc')),
        initialSettings: InAppWebViewSettings(
          isInspectable: kDebugMode,
          preferredContentMode: UserPreferredContentMode.MOBILE,
          userAgent: _userAgent,
          useShouldOverrideUrlLoading: true,
          mediaPlaybackRequiresUserGesture: false,
          clearCache: true, // Auto clear cache on init
          cacheEnabled: false, // Disable cache
        ),
        onWebViewCreated: (controller) {
          debugPrint('proses kirim: Background Headless WebView created.');
          // Clear cookies on create
          CookieManager.instance().deleteAllCookies();
        },
        onLoadStop: (controller, url) {
          debugPrint('proses kirim: Background Headless WebView loaded: $url');
          if (!_initCompleter.isCompleted) {
            _initCompleter.complete();
          }
        },
        onConsoleMessage: (controller, consoleMessage) {
          debugPrint(
            'proses kirim: Headless Console: ${consoleMessage.message}',
          );
        },
      );

      await _headlessWebView!.run();
      _isWebViewInitialized = true;
      debugPrint('proses kirim: Background WebView initialized.');
    } catch (e) {
      debugPrint('proses kirim: Gagal init WebView: $e');
      if (!_initCompleter.isCompleted) _initCompleter.completeError(e);
    }
  }

  // Getter untuk controller agar bisa dipasang di Widget tree (hidden)
  // Tidak relevan lagi dengan HeadlessInAppWebView karena tidak perlu dipasang di tree

  /// Dipanggil setelah sukses login manual via WebView
  void setCredentials({
    required String cookie,
    required String csrfToken,
    required String gcToken,
    required String userAgent,
  }) {
    _cookieHeader = cookie;
    _csrfToken = csrfToken;
    _gcToken = gcToken;
    _userAgent = userAgent;

    // Update User Agent di WebView background juga
    if (_isWebViewInitialized && _headlessWebView != null) {
      _headlessWebView!.webViewController?.setSettings(
        settings: InAppWebViewSettings(userAgent: userAgent),
      );
    }

    debugPrint(
      'proses kirim: Credentials tersimpan. CSRF: $_csrfToken, GC: $_gcToken',
    );
  }

  /// Cek apakah kita punya credentials yang cukup untuk kirim data
  bool get hasCredentials {
    // Kriteria 1: Punya Token lengkap (GC Token + CSRF Token)
    final hasTokens =
        (_csrfToken?.isNotEmpty ?? false) && (_gcToken?.isNotEmpty ?? false);

    // Kriteria 2: Punya Strong Cookie (Laravel Session + XSRF Token)
    // Ini cukup untuk melakukan request, bahkan jika gc_token belum ter-parse.
    final hasStrongCookie =
        _cookieHeader != null &&
        _cookieHeader!.contains('laravel_session') &&
        _cookieHeader!.contains('XSRF-TOKEN');

    return hasTokens || hasStrongCookie;
  }

  String? get currentGcToken => _gcToken;
  String? get cookieHeader => _cookieHeader;
  String? get userAgent => _userAgent;

  /// Login otomatis menggunakan Headless WebView (meniru Python Playwright)
  Future<Map<String, dynamic>> automatedLogin({
    required String username,
    required String password,
  }) async {
    debugPrint('proses kirim: Memulai automated login untuk $username...');

    // Rotate UA first
    _rotateUserAgent();

    // FORCE Re-init WebView untuk memastikan sesi bersih
    // Ini krusial untuk ganti akun agar tidak nyangkut di sesi lama
    await _initWebView(forceRecreate: true);

    final controller = _headlessWebView?.webViewController;
    if (controller == null) {
      return {'status': 'error', 'message': 'WebView not initialized'};
    }

    try {
      // Clear All Storage & Cookies Explicitly
      debugPrint('proses kirim: Clearing all cookies and storage...');
      await CookieManager.instance().deleteAllCookies();
      try {
        await WebStorageManager.instance().deleteAllData();
      } catch (e) {
        // Ignore if not supported
      }

      // Clear cache again via controller if possible
      try {
        await controller.clearCache();
      } catch (e) {
        debugPrint('proses kirim: Warning: Failed to clear cache: $e');
      }

      // Update Settings with new UA
      await controller.setSettings(
        settings: InAppWebViewSettings(userAgent: _userAgent),
      );

      // Go to Login Page
      debugPrint('proses kirim: Navigasi ke login page...');
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri('$baseUrl/login')),
      );

      // Helper to wait for selector
      Future<bool> waitForSelector(
        String selector, {
        int timeoutMs = 15000,
      }) async {
        int elapsed = 0;
        while (elapsed < timeoutMs) {
          final result = await controller.evaluateJavascript(
            source: "document.querySelector('$selector') != null",
          );
          if (result == true) return true;
          await Future.delayed(const Duration(milliseconds: 500));
          elapsed += 500;
        }
        return false;
      }

      // Wait for #login-sso
      if (!await waitForSelector('#login-sso')) {
        debugPrint('proses kirim: Login page timeout or SSO button missing');
        return {'status': 'error', 'message': 'Login page timeout'};
      }

      // Click SSO
      debugPrint('proses kirim: Clicking SSO...');
      await controller.evaluateJavascript(
        source: "document.querySelector('#login-sso').click();",
      );

      // Wait for Username Input (SSO Page)
      if (!await waitForSelector('input[name="username"]')) {
        debugPrint('proses kirim: SSO page timeout');
        return {'status': 'error', 'message': 'SSO page timeout'};
      }

      // Fill Credentials
      debugPrint('proses kirim: Filling credentials...');
      final safeUser = username.replaceAll("'", "\\'");
      final safePass = password.replaceAll("'", "\\'");

      await controller.evaluateJavascript(
        source:
            """
        document.querySelector('input[name="username"]').value = '$safeUser';
        document.querySelector('input[name="password"]').value = '$safePass';
        document.querySelector('input[type="submit"]').click();
      """,
      );

      // Wait for Redirect back to Matchapro
      debugPrint('proses kirim: Waiting for redirect to dashboard...');
      int elapsed = 0;
      bool loggedIn = false;
      while (elapsed < 60000) {
        // 60s timeout
        final url = (await controller.getUrl())?.toString() ?? '';

        // Cek OTP
        final hasOtp = await controller.evaluateJavascript(
          source: "document.querySelector('input[name=\"otp\"]') != null",
        );
        if (hasOtp == true) {
          // Jika butuh OTP, kita tidak bisa lanjut otomatis di background
          return {
            'status': 'error',
            'message': 'OTP Diperlukan. Silakan gunakan Login Manual.',
          };
        }

        if (url.contains('matchapro.web.bps.go.id') &&
            !url.contains('login') &&
            !url.contains('sso')) {
          loggedIn = true;
          break;
        }

        // Cek jika ada error di halaman
        final isError = await controller.evaluateJavascript(
          source:
              "document.body.innerText.includes('Kombinasi username/email dan password salah')",
        );
        if (isError == true) {
          return {'status': 'error', 'message': 'Password salah'};
        }

        await Future.delayed(const Duration(seconds: 1));
        elapsed += 1000;
      }

      if (!loggedIn) {
        return {'status': 'error', 'message': 'Login timeout (stuck)'};
      }

      debugPrint('proses kirim: Login berhasil, extracting tokens...');

      // Extract Tokens
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(baseUrl),
      );
      final cookieStr = cookies.map((c) => '${c.name}=${c.value}').join('; ');

      final tokens = await controller.evaluateJavascript(
        source: """
        (function() {
            let gc_token = '';
            let csrf_token = '';
            let user_name = '';
            
            try {
                let match = document.body.innerHTML.match(/let\\s+gcSubmitToken\\s*=\s*(['"])([^'"]+)\\1/);
                if (match) gc_token = match[2];
            } catch(e) {}
            
            if (!gc_token) {
                let el = document.querySelector('input[name="gc_token"]');
                if (el) gc_token = el.value;
            }
            
            let meta = document.querySelector('meta[name="csrf-token"]');
            if (meta) csrf_token = meta.content;
            
            let userEl = document.querySelector('.user-name.fw-bolder') || 
                         document.querySelector('.dropdown-user .username') || 
                         document.querySelector('.user-panel .info p');
            if (userEl) user_name = userEl.innerText.trim();
            
            return {gc_token, csrf_token, user_name};
        })();
      """,
      );

      if (tokens != null && tokens is Map) {
        setCredentials(
          cookie: cookieStr,
          csrfToken: tokens['csrf_token'] ?? '',
          gcToken: tokens['gc_token'] ?? '',
          userAgent: _userAgent,
        );
        return {
          'status': 'success',
          'userName': tokens['user_name'],
          'loginId': username,
          'gcToken': tokens['gc_token'],
          'csrfToken': tokens['csrf_token'],
        };
      }

      return {'status': 'error', 'message': 'Failed to extract tokens'};
    } catch (e) {
      debugPrint('proses kirim: Automated Login Exception: $e');
      return {'status': 'error', 'message': 'Exception: $e'};
    }
  }

  /// Refresh session: Mengambil ulang data user dan token dari halaman dashboard
  Future<Map<String, String>?> refreshSession() async {
    if (_cookieHeader == null) return null;

    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/dirgc'),
        headers: {
          'Cookie': _cookieHeader!,
          'User-Agent': _userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        },
      );

      if (response.statusCode == 200) {
        final html = response.body;
        String userName = '';
        String gcToken = '';
        String csrfToken = '';

        // Extract Username
        // Regex untuk .user-name.fw-bolder
        final userRegex = RegExp(
          r'<span[^>]*class="[^"]*user-name[^"]*fw-bolder[^"]*"[^>]*>\s*([^<]+)\s*<\/span>',
        );
        final userMatch = userRegex.firstMatch(html);
        if (userMatch != null) {
          userName = userMatch.group(1)?.trim() ?? '';
        } else {
          // Fallback regex
          final fallbackRegex = RegExp(
            r'class="[^"]*(username|info)[^"]*">\s*<p>\s*([^<]+)\s*<\/p>',
          );
          final fallbackMatch = fallbackRegex.firstMatch(html);
          if (fallbackMatch != null) {
            userName = fallbackMatch.group(2)?.trim() ?? '';
          }
        }

        // Extract GC Token
        // Regex: let gcSubmitToken = '...'; OR "..."
        // Menggunakan r'''...''' untuk menangani quote campuran
        final gcRegex = RegExp(
          r'''let\s+gcSubmitToken\s*=\s*['"]([^'"]+)['"]''',
        );
        final gcMatch = gcRegex.firstMatch(html);
        if (gcMatch != null) {
          gcToken = gcMatch.group(1) ?? '';
        } else {
          // Try input hidden
          final gcInputRegex = RegExp(r'name="gc_token"\s+value="([^"]+)"');
          final gcInputMatch = gcInputRegex.firstMatch(html);
          if (gcInputMatch != null) {
            gcToken = gcInputMatch.group(1) ?? '';
          }
        }

        // Extract CSRF Token
        final csrfRegex = RegExp(r'name="csrf-token"\s+content="([^"]+)"');
        final csrfMatch = csrfRegex.firstMatch(html);
        if (csrfMatch != null) {
          csrfToken = csrfMatch.group(1) ?? '';
        }

        return {
          'userName': userName,
          'gcToken': gcToken,
          'csrfToken': csrfToken,
        };
      }
      return null;
    } catch (e) {
      debugPrint('Refresh session failed: $e');
      return null;
    }
  }

  /// Kirim data konfirmasi user via WebView JS Injection.
  /// Ini menghindari masalah HttpOnly Cookie dan Error 419.
  Future<Map<String, dynamic>?> logout() async {
    try {
      debugPrint('proses kirim: Memulai proses logout...');

      // 1. Pastikan Controller Siap
      if (_headlessWebView == null || !_isWebViewInitialized) {
        debugPrint('proses kirim: Init WebView sementara untuk logout...');
        await _initWebView();
      }

      final controller = _headlessWebView?.webViewController;

      if (controller != null && _isWebViewInitialized) {
        // 2. Load Base URL agar domain context benar
        // Cookie sudah otomatis shared dengan InAppWebViewLoginDialog
        debugPrint('proses kirim: Loading context domain...');
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri('$baseUrl/dirgc')),
        );

        // Tunggu sebentar
        await Future.delayed(const Duration(seconds: 3));

        // Cek jika token ada
        final token =
            _csrfToken ??
            ''; // Logout endpoint expects _token based on user info

        debugPrint('proses kirim: Mengirim request logout via WebView JS...');

        // Kita gunakan evaluateJavascript untuk membuat form post logout
        final logoutScript =
            '''
          var form = document.createElement("form");
          form.setAttribute("method", "POST");
          form.setAttribute("action", "$baseUrl/logout");

          var hiddenField = document.createElement("input");
          hiddenField.setAttribute("type", "hidden");
          hiddenField.setAttribute("name", "_token");
          hiddenField.setAttribute("value", "$token");

          form.appendChild(hiddenField);
          document.body.appendChild(form);
          form.submit();
        ''';

        await controller.evaluateJavascript(source: logoutScript);

        // Tunggu sebentar agar request terproses
        await Future.delayed(const Duration(seconds: 2));

        // Reset local state
        _cookieHeader = null;
        _csrfToken = null;
        _gcToken = null;

        // Clear WebView cookies & Storage
        try {
          await CookieManager.instance().deleteAllCookies();
          await WebStorageManager.instance().deleteAllData();
        } catch (e) {
          debugPrint(
            'proses kirim: Warning: Failed to clear cookies/storage (logout): $e',
          );
        }

        // Dispose WebView agar sesi benar-benar mati
        await _disposeWebView();

        return {'status': 'success', 'message': 'Logout berhasil'};
      }

      return {'status': 'failed', 'message': 'WebView gagal diinisialisasi'};
    } catch (e) {
      debugPrint('proses kirim: Logout Error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> konfirmasiUser({
    required String perusahaanId,
    required String latitude,
    required String longitude,
    required String hasilGc,
  }) async {
    if (!hasCredentials) {
      debugPrint('proses kirim: Gagal. Belum login / credentials kosong.');
      return null;
    }

    // 1. Prioritaskan HTTP Request Biasa (Tanpa WebView)
    final hasSession = _cookieHeader?.contains('laravel_session') ?? false;
    final hasXsrf = _cookieHeader?.contains('XSRF-TOKEN') ?? false;

    if (hasSession && hasXsrf) {
      return _konfirmasiUserViaHttp(
        perusahaanId: perusahaanId,
        latitude: latitude,
        longitude: longitude,
        hasilGc: hasilGc,
      );
    } else {}

    // 2. Fallback: Kirim data konfirmasi user via WebView JS Injection.
    try {
      await _initCompleter.future;
    } catch (e) {
      debugPrint('proses kirim: Gagal menunggu WebView init: $e');
      return null;
    }

    if (!_isWebViewInitialized || _headlessWebView == null) {
      debugPrint('proses kirim: Gagal. WebView belum siap.');
      return null;
    }

    final controller = _headlessWebView!.webViewController!;
    final url = '$baseUrl/dirgc/konfirmasi-user';

    try {
      // Cek apakah kita sudah di domain yang benar
      final currentUrl = await controller.getUrl();
      debugPrint('proses kirim: Current URL: $currentUrl');

      bool needLoad = true;
      if (currentUrl != null &&
          currentUrl.toString().contains('matchapro.web.bps.go.id')) {
        // Sudah di domain yang benar
        needLoad = false;
      }

      if (needLoad) {
        debugPrint('proses kirim: Reloading base URL untuk setup origin...');
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri('$baseUrl/dirgc')),
        );

        // Tunggu hingga halaman benar-benar siap
        bool ready = false;
        int retry = 0;
        while (!ready && retry < 20) {
          await Future.delayed(const Duration(milliseconds: 500));
          try {
            // Cek progress
            final progress = await controller.getProgress();
            if (progress == 100) ready = true;
          } catch (_) {}
          retry++;
        }

        if (!ready) {
          debugPrint('proses kirim: Timeout waiting for page load.');
          // Try proceeding anyway
        }
      }

      // DEBUG: Cek cookie yang terlihat oleh JS
      final visibleCookie = await controller.evaluateJavascript(
        source: "document.cookie",
      );
      debugPrint('proses kirim: Background JS Cookie Visible: $visibleCookie');

      debugPrint('proses kirim: Injecting JS fetch...');

      // Setup channel untuk menerima hasil menggunakan addJavaScriptHandler
      String? fetchResult;
      final completer = Completer<void>();

      controller.addJavaScriptHandler(
        handlerName: 'FlutterChannel',
        callback: (args) {
          if (args.isNotEmpty) {
            fetchResult = args[0].toString();
            if (!completer.isCompleted) {
              completer.complete();
            }
          }
        },
      );

      // JavaScript
      final jsScript =
          '''
        (function() {
            var formData = new FormData();
            formData.append('perusahaan_id', '$perusahaanId');
            formData.append('latitude', '$latitude');
            formData.append('longitude', '$longitude');
            formData.append('hasilgc', '$hasilGc');
            formData.append('gc_token', '$_gcToken');
            formData.append('_token', '$_csrfToken');

            fetch('$url', {
                method: 'POST',
                headers: {
                    'X-Requested-With': 'XMLHttpRequest',
                    'Accept': 'application/json, text/javascript, */*; q=0.01'
                },
                body: formData
            })
            .then(function(response) {
                return response.text().then(function(text) {
                    return {
                        status: response.status,
                        body: text
                    };
                });
            })
            .then(function(result) {
                window.flutter_inappwebview.callHandler('FlutterChannel', JSON.stringify(result));
            })
            .catch(function(error) {
                window.flutter_inappwebview.callHandler('FlutterChannel', JSON.stringify({
                    status: 0,
                    body: error.toString()
                }));
            });
        })();
      ''';

      // Jalankan script
      await controller.evaluateJavascript(source: jsScript);

      // Tunggu hasil
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('proses kirim: Timeout waiting for fetch result');
        },
      );

      // Cleanup channel
      controller.removeJavaScriptHandler(handlerName: 'FlutterChannel');

      if (fetchResult == null) {
        debugPrint('proses kirim: No result from fetch');
        return null;
      }

      debugPrint('proses kirim: Fetch Result: $fetchResult');

      final map = jsonDecode(fetchResult!);
      final status = map['status'];
      final bodyStr = map['body'];

      if (status == 200 || status == 429) {
        try {
          return jsonDecode(bodyStr) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('proses kirim: Gagal decode response JSON: $bodyStr');
          return null;
        }
      } else if (status == 419) {
        debugPrint('proses kirim: Gagal 419 (CSRF Token Mismatch) via JS.');
        return null;
      } else {
        debugPrint('proses kirim: Gagal ($status). Body: $bodyStr');
        return null;
      }
    } catch (e) {
      debugPrint('proses kirim: Error Exception: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getDraftTambahUsaha() async {
    final url = Uri.parse('$baseUrl/dirgc/rtr-draft-tambah-usaha');

    if (_cookieHeader == null) return null;

    final headers = {
      'Cookie': _cookieHeader!,
      'User-Agent': _userAgent,
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'X-Requested-With': 'XMLHttpRequest',
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'Origin': baseUrl,
      'Referer': '$baseUrl/dirgc',
      'X-CSRF-TOKEN': _csrfToken ?? '',
    };

    final body = {'_token': _csrfToken ?? ''};

    try {
      final response = await _client.post(url, headers: headers, body: body);
      debugPrint('getDraftTambahUsaha: HTTP Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('getDraftTambahUsaha Error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> saveDraftTambahUsaha({
    required String namaUsaha,
    required String alamat,
    required String provinsiId,
    required String kabupatenId,
    required String kecamatanId,
    required String desaId,
    required String latitude,
    required String longitude,
  }) async {
    final url = Uri.parse('$baseUrl/dirgc/draft-tambah-usaha');

    if (_cookieHeader == null) return null;

    final headers = {
      'Cookie': _cookieHeader!,
      'User-Agent': _userAgent,
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'X-Requested-With': 'XMLHttpRequest',
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'Origin': baseUrl,
      'Referer': '$baseUrl/dirgc',
      'X-CSRF-TOKEN': _csrfToken ?? '',
    };

    final body = {
      '_token': _csrfToken ?? '',
      'nama_usaha': namaUsaha,
      'alamat': alamat,
      'provinsi': provinsiId,
      'kabupaten': kabupatenId,
      'kecamatan': kecamatanId,
      'desa': desaId,
      'latitude': latitude,
      'longitude': longitude,
      'confirmSubmit': 'true',
    };

    debugPrint('saveDraftTambahUsaha: Payload: $body');

    try {
      final response = await _client.post(url, headers: headers, body: body);
      debugPrint('saveDraftTambahUsaha: HTTP Status: ${response.statusCode}');
      debugPrint('saveDraftTambahUsaha: Response Body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('saveDraftTambahUsaha Error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> cancelKonfirmasiUser({
    required String perusahaanId,
  }) async {
    final url = Uri.parse('$baseUrl/dirgc/konfirmasi-user-cancel');

    if (_cookieHeader == null) return null;

    final headers = {
      'Cookie': _cookieHeader!,
      'User-Agent': _userAgent,
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'X-Requested-With': 'XMLHttpRequest',
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'Origin': baseUrl,
      'Referer': '$baseUrl/dirgc',
      'X-CSRF-TOKEN': _csrfToken ?? '',
    };

    final body = {'perusahaan_id': perusahaanId, '_token': _csrfToken ?? ''};

    try {
      final response = await _client.post(url, headers: headers, body: body);
      debugPrint('cancelKonfirmasiUser: HTTP Status: ${response.statusCode}');
      debugPrint('cancelKonfirmasiUser: HTTP Body: ${response.body}');

      if (response.statusCode == 200) {
        // Response might be empty or JSON, handling safely
        if (response.body.isNotEmpty) {
          try {
            return jsonDecode(response.body) as Map<String, dynamic>;
          } catch (_) {
            return {'status': 'success', 'message': 'Cancelled'};
          }
        }
        return {'status': 'success', 'message': 'Cancelled'};
      }
      return null;
    } catch (e) {
      debugPrint('cancelKonfirmasiUser Error: $e');
      return null;
    }
  }

  // Metode helper cookie lama dihapus/diabaikan
  void _mergeSetCookie(Map<String, String> headers) {}

  /// Metode untuk mendapatkan cookie header string dari Shared Controller
  Future<String> getVisibleCookie() async {
    if (_headlessWebView == null || !_isWebViewInitialized) return '';
    try {
      final controller = _headlessWebView!.webViewController!;
      final result = await controller.evaluateJavascript(
        source: 'document.cookie',
      );
      return result.toString();
    } catch (e) {
      return '';
    }
  }

  Future<Map<String, dynamic>?> _konfirmasiUserViaHttp({
    required String perusahaanId,
    required String latitude,
    required String longitude,
    required String hasilGc,
  }) async {
    final url = Uri.parse('$baseUrl/dirgc/konfirmasi-user');

    // Pastikan headers lengkap meniru browser
    final headers = {
      'Cookie': _cookieHeader!,
      'User-Agent': _userAgent,
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'X-Requested-With': 'XMLHttpRequest',
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'Origin': baseUrl,
      'Referer': '$baseUrl/dirgc',
      // Penting: X-CSRF-TOKEN
      'X-CSRF-TOKEN': _csrfToken ?? '',
    };

    final body = {
      'perusahaan_id': perusahaanId,
      'latitude': latitude,
      'longitude': longitude,
      'hasilgc': hasilGc,
      'gc_token': _gcToken ?? '',
      '_token': _csrfToken ?? '',
    };

    try {
      final response = await _client.post(url, headers: headers, body: body);
      debugPrint('proses kirim: HTTP Status: ${response.statusCode}');
      debugPrint('proses kirim: HTTP Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 429) {
        try {
          return jsonDecode(response.body) as Map<String, dynamic>;
        } catch (e) {
          debugPrint(
            'proses kirim: Gagal decode response JSON: ${response.body}',
          );
          return null;
        }
      } else if (response.statusCode == 419) {
        debugPrint('proses kirim: Gagal 419 (CSRF Token Mismatch) via HTTP.');
        return null;
      } else {
        debugPrint(
          'proses kirim: Gagal (${response.statusCode}). Body: ${response.body}',
        );
        // Jika 400 dan ada body JSON, kembalikan agar bisa dihandle caller
        if (response.statusCode == 400 && response.body.isNotEmpty) {
          try {
            return jsonDecode(response.body) as Map<String, dynamic>;
          } catch (_) {
            return null;
          }
        }
        return null;
      }
    } catch (e) {
      debugPrint('proses kirim: Error Exception HTTP: $e');
      return null;
    }
  }
}
