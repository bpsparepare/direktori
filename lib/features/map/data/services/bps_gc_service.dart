import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
// Import for macOS support
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

class BpsGcService {
  final String baseUrl = 'https://matchapro.web.bps.go.id';

  final http.Client _client;

  // Controller tunggal yang dishare antara Login Dialog dan Service
  // Ini menjamin sesi (Cookie) selalu sinkron karena menggunakan instance yang sama.
  WebViewController? _sharedController;
  final Completer<void> _initCompleter = Completer<void>();
  final Completer<void> _pageLoadCompleter = Completer<void>();
  bool _isWebViewInitialized = false;

  String? _csrfToken;
  String? _gcToken;
  String? _cookieHeader;
  String _userAgent =
      'Mozilla/5.0 (Linux; Android 16; ONEPLUS 15 Build/SKQ1.211202.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/143.0.7499.192 Mobile Safari/537.36';

  BpsGcService({http.Client? client}) : _client = client ?? http.Client();

  /// Mengambil atau membuat WebViewController.
  /// Dipanggil oleh UI (Login Dialog) agar menggunakan controller yang sama dengan Service.
  Future<WebViewController> getController() async {
    if (_sharedController != null) return _sharedController!;

    await _initWebView();
    return _sharedController!;
  }

  Future<void> _initWebView() async {
    if (_isWebViewInitialized && _sharedController != null) return;

    try {
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
        ..setUserAgent(_userAgent)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (String url) {
              debugPrint('proses kirim: Background Page Loaded: $url');
              if (!_pageLoadCompleter.isCompleted) {
                _pageLoadCompleter.complete();
              }
            },
            onWebResourceError: (error) {
              debugPrint(
                'proses kirim: Background Web Resource Error: ${error.description}',
              );
            },
          ),
        );

      _sharedController = controller;
      _isWebViewInitialized = true;
      if (!_initCompleter.isCompleted) _initCompleter.complete();
      debugPrint('proses kirim: Background WebView initialized.');
    } catch (e) {
      debugPrint('proses kirim: Gagal init WebView: $e');
      if (!_initCompleter.isCompleted) _initCompleter.completeError(e);
    }
  }

  // Getter untuk controller agar bisa dipasang di Widget tree (hidden)
  WebViewController? get backgroundController =>
      _isWebViewInitialized ? _sharedController : null;

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
    if (_isWebViewInitialized && _sharedController != null) {
      _sharedController!.setUserAgent(userAgent);
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

  /// Kirim data konfirmasi user via WebView JS Injection.
  /// Ini menghindari masalah HttpOnly Cookie dan Error 419.
  /// Kirim data konfirmasi user via WebView JS Injection.
  /// Ini menghindari masalah HttpOnly Cookie dan Error 419.
  Future<Map<String, dynamic>?> konfirmasiUser({
    required String perusahaanId,
    required String latitude,
    required String longitude,
    required String hasilGc,
  }) async {
    debugPrint('proses kirim: --- Mulai Pengiriman Data ---');

    if (!hasCredentials) {
      debugPrint('proses kirim: Gagal. Belum login / credentials kosong.');
      return null;
    }

    // 1. Prioritaskan HTTP Request Biasa (Tanpa WebView)
    // Syarat: Cookie harus lengkap (mengandung laravel_session dan XSRF-TOKEN)
    // Ini adalah cara yang paling mirip dengan Python dan lebih reliable jika cookie valid.
    final hasSession = _cookieHeader?.contains('laravel_session') ?? false;
    final hasXsrf = _cookieHeader?.contains('XSRF-TOKEN') ?? false;

    // PERBAIKAN: Selalu gunakan HTTP Direct jika session ada,
    // bahkan jika gc_token kosong (nanti kita coba fetch ulang token jika perlu, atau biarkan kosong)
    if (hasSession && hasXsrf) {
      debugPrint('proses kirim: Menggunakan HTTP Request Biasa (Direct)');
      return _konfirmasiUserViaHttp(
        perusahaanId: perusahaanId,
        latitude: latitude,
        longitude: longitude,
        hasilGc: hasilGc,
      );
    } else {
      debugPrint('proses kirim: Cookie tidak lengkap untuk HTTP Biasa.');
      debugPrint(
        'proses kirim: Fallback ke WebView Injection (Mengandalkan Cookie Internal WebView).',
      );
    }

    // 2. Fallback: Kirim data konfirmasi user via WebView JS Injection.
    // Ini menghindari masalah HttpOnly Cookie dan Error 419 jika cookie tidak terbaca di Dart.
    // Tunggu inisialisasi WebView selesai
    try {
      await _initCompleter.future;
    } catch (e) {
      debugPrint('proses kirim: Gagal menunggu WebView init: $e');
      return null;
    }

    if (!_isWebViewInitialized) {
      debugPrint('proses kirim: Gagal. WebView belum siap.');
      return null;
    }

    final url = '$baseUrl/dirgc/konfirmasi-user';

    try {
      // Cek apakah kita sudah di domain yang benar
      final currentUrl = await _sharedController!.currentUrl();
      debugPrint('proses kirim: Current URL: $currentUrl');

      bool needLoad = true;
      if (currentUrl != null &&
          currentUrl.contains('matchapro.web.bps.go.id')) {
        // Sudah di domain yang benar. Cek apakah readyState complete.
        try {
          final state = await _sharedController!.runJavaScriptReturningResult(
            "document.readyState",
          );
          if (state.toString().contains('complete')) {
            debugPrint(
              'proses kirim: Sudah di domain yang benar dan ready. Skip reload.',
            );
            needLoad = false;
          }
        } catch (_) {}
      }

      if (needLoad) {
        debugPrint('proses kirim: Reloading base URL untuk setup origin...');
        await _sharedController!.loadRequest(Uri.parse('$baseUrl/dirgc'));

        // Tunggu hingga halaman benar-benar siap
        bool ready = false;
        int retry = 0;
        while (!ready && retry < 20) {
          await Future.delayed(const Duration(milliseconds: 500));
          try {
            final state = await _sharedController!.runJavaScriptReturningResult(
              "document.readyState",
            );
            debugPrint('proses kirim: Page State: $state');
            if (state.toString().contains('complete')) {
              ready = true;
            }
          } catch (_) {}
          retry++;
        }

        if (!ready) {
          debugPrint('proses kirim: Timeout waiting for page load.');
          return null;
        }
      }

      // DEBUG: Cek cookie yang terlihat oleh JS
      final visibleCookie = await _sharedController!
          .runJavaScriptReturningResult("document.cookie");
      debugPrint('proses kirim: Background JS Cookie Visible: $visibleCookie');

      debugPrint('proses kirim: Injecting JS fetch...');

      // SOLUSI 1: Gunakan JavaScriptChannel untuk komunikasi 2-arah
      // Setup channel untuk menerima hasil
      String? fetchResult;
      final completer = Completer<void>();

      _sharedController!.addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (JavaScriptMessage message) {
          fetchResult = message.message;
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      );

      // JavaScript yang kompatibel dengan semua platform
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
                FlutterChannel.postMessage(JSON.stringify(result));
            })
            .catch(function(error) {
                FlutterChannel.postMessage(JSON.stringify({
                    status: 0,
                    body: error.toString()
                }));
            });
        })();
      ''';

      // Jalankan script (tidak menunggu return value)
      await _sharedController!.runJavaScript(jsScript);

      // Tunggu hasil dari channel (dengan timeout)
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('proses kirim: Timeout waiting for fetch result');
        },
      );

      // Cleanup channel
      _sharedController!.removeJavaScriptChannel('FlutterChannel');

      if (fetchResult == null) {
        debugPrint('proses kirim: No result from fetch');
        return null;
      }

      debugPrint('proses kirim: Fetch Result: $fetchResult');

      final map = jsonDecode(fetchResult!);
      final status = map['status'];
      final bodyStr = map['body'];

      if (status == 200) {
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
      // Cleanup channel jika error
      try {
        _sharedController!.removeJavaScriptChannel('FlutterChannel');
      } catch (_) {}
      return null;
    }
  }

  // Metode helper cookie lama dihapus/diabaikan
  void _mergeSetCookie(Map<String, String> headers) {}

  /// Metode untuk mendapatkan cookie header string dari Shared Controller
  /// Berguna untuk debugging atau jika kita ingin menggunakan http client standar nanti.
  /// Catatan: Ini hanya mengembalikan cookie yang visible oleh JS (non-HttpOnly).
  Future<String> getVisibleCookie() async {
    if (_sharedController == null || !_isWebViewInitialized) return '';
    try {
      final result = await _sharedController!.runJavaScriptReturningResult(
        'document.cookie',
      );
      String cookie = result.toString();
      if (cookie.startsWith('"') && cookie.endsWith('"')) {
        cookie = jsonDecode(cookie);
      }
      return cookie;
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

      if (response.statusCode == 200) {
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
        return null;
      }
    } catch (e) {
      debugPrint('proses kirim: Error Exception HTTP: $e');
      return null;
    }
  }
}
