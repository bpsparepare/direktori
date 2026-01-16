import 'dart:convert';
import 'package:http/http.dart' as http;

class BpsGcService {
  final String baseUrl = 'https://matchapro.web.bps.go.id';
  final http.Client _client;
  String? _csrfToken;
  String? _cookieHeader;
  DateTime? _lastCsrfFetch;
  final Duration _csrfTtl = const Duration(minutes: 15);

  BpsGcService({http.Client? client}) : _client = client ?? http.Client();

  void setCookiesFromHeader(String cookieString) {
    _cookieHeader = cookieString;
  }

  String? get cookieHeader => _cookieHeader;

  Future<void> autoGetCsrfToken() async {
    final url = Uri.parse('$baseUrl/dirgc');
    final response = await _client.get(
      url,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
        'X-Requested-With': 'XMLHttpRequest',
        'Cookie': _cookieHeader ?? '',
      },
    );

    _mergeSetCookie(response.headers);

    final body = response.body;
    final metaRegex = RegExp(
      r'<meta name="csrf-token" content="([^"]+)"',
      caseSensitive: false,
    );
    final inputRegex = RegExp(
      r'<input[^>]+name="_token"[^>]+value="([^"]+)"',
      caseSensitive: false,
    );

    String? token;
    final m1 = metaRegex.firstMatch(body);
    if (m1 != null) {
      token = m1.group(1);
    } else {
      final m2 = inputRegex.firstMatch(body);
      if (m2 != null) {
        token = m2.group(1);
      }
    }

    _csrfToken = token;
    _lastCsrfFetch = DateTime.now();
  }

  Future<void> _ensureFreshCsrf() async {
    if (_cookieHeader == null || _cookieHeader!.isEmpty) return;
    final now = DateTime.now();
    if (_csrfToken == null ||
        _lastCsrfFetch == null ||
        now.difference(_lastCsrfFetch!) > _csrfTtl) {
      await autoGetCsrfToken();
    }
  }

  bool _looksLikeLoginPage(String body) {
    final b = body.toLowerCase();
    return b.contains('please sign-in') ||
        b.contains('sign in with sso bps') ||
        b.contains('welcome to matchapro');
  }

  Future<Map<String, dynamic>?> konfirmasiUser({
    required String perusahaanId,
    required String latitude,
    required String longitude,
    required String hasilGc,
    required String gcToken,
  }) async {
    await _ensureFreshCsrf();
    final url = Uri.parse('$baseUrl/dirgc/konfirmasi-user');

    final body = {
      'perusahaan_id': perusahaanId,
      'latitude': latitude,
      'longitude': longitude,
      'hasilgc': hasilGc,
      'gc_token': gcToken,
      '_token': _csrfToken ?? '',
    };

    final response = await _client.post(
      url,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'X-Requested-With': 'XMLHttpRequest',
        'Cookie': _cookieHeader ?? '',
      },
      body: body,
    );

    _mergeSetCookie(response.headers);

    if (response.statusCode != 200) {
      // Retry once after refreshing CSRF if unauthorized/forbidden or HTML login page
      await autoGetCsrfToken();
      final retry = await _client.post(
        url,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'X-Requested-With': 'XMLHttpRequest',
          'Cookie': _cookieHeader ?? '',
        },
        body: {...body, '_token': _csrfToken ?? ''},
      );
      _mergeSetCookie(retry.headers);
      if (retry.statusCode != 200) return null;
      final rb = retry.body;
      if (_looksLikeLoginPage(rb)) return null;
      return jsonDecode(rb) as Map<String, dynamic>;
    }

    final respBody = response.body;
    if (_looksLikeLoginPage(respBody)) {
      // Session invalid; caller should prompt user to re-login/paste cookie
      return null;
    }

    return jsonDecode(respBody) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> konfirmasiUserWithRetry({
    required String perusahaanId,
    required String latitude,
    required String longitude,
    required String hasilGc,
    required String gcToken,
    int maxRetries = 2,
  }) async {
    for (var i = 0; i < maxRetries; i++) {
      final resp = await konfirmasiUser(
        perusahaanId: perusahaanId,
        latitude: latitude,
        longitude: longitude,
        hasilGc: hasilGc,
        gcToken: gcToken,
      );
      if (resp != null) return resp;
      await autoGetCsrfToken();
      await Future.delayed(Duration(milliseconds: 400 * (i + 1)));
    }
    return null;
  }

  Future<void> keepAlive() async {
    if (_cookieHeader == null || _cookieHeader!.isEmpty) return;
    await autoGetCsrfToken();
  }

  Future<bool> isSessionValid() async {
    try {
      final url = Uri.parse('$baseUrl/dirgc');
      final response = await _client.get(
        url,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
          'Accept': '*/*',
          'Accept-Language': 'en-US,en;q=0.9',
          'X-Requested-With': 'XMLHttpRequest',
          'Cookie': _cookieHeader ?? '',
        },
      );
      _mergeSetCookie(response.headers);
      return !_looksLikeLoginPage(response.body);
    } catch (_) {
      return false;
    }
  }

  void _mergeSetCookie(Map<String, String> headers) {
    final setCookie = headers.entries
        .firstWhere(
          (e) => e.key.toLowerCase() == 'set-cookie',
          orElse: () => const MapEntry('', ''),
        )
        .value;
    if (setCookie.isEmpty) return;
    final regex = RegExp(r'(^|,)\s*([^=;,\s]+)=([^;]+)');
    final matches = regex.allMatches(setCookie);
    final Map<String, String> jar = {};
    if (_cookieHeader != null && _cookieHeader!.isNotEmpty) {
      for (final part in _cookieHeader!.split(';')) {
        final p = part.trim();
        if (p.isEmpty) continue;
        final idx = p.indexOf('=');
        if (idx > 0) {
          final name = p.substring(0, idx).trim();
          final val = p.substring(idx + 1).trim();
          if (name.isNotEmpty) jar[name] = val;
        }
      }
    }
    for (final m in matches) {
      final name = m.group(2)?.trim();
      final val = m.group(3)?.trim();
      if (name != null && name.isNotEmpty && val != null && val.isNotEmpty) {
        jar[name] = val;
      }
    }
    final merged = jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
    _cookieHeader = merged;
  }
}
