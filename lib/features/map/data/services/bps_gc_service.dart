import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BpsGcService {
  final String baseUrl = 'https://matchapro.web.bps.go.id';
  static const String _forcedToken = 'X8Gt3z8rWjMXOB0UW3A1ZbQ0Xmu8x9Fln2nLrz39';
  static const String _forcedGcToken =
      'X8Gt3z8rWjMXOB0UW3A1ZbQ0Xmu8x9Fln2nLrz39';
  static const String _forcedCookie =
      r'f5avraaaaaaaaaaaaaaaa_session_=BOJKEELEIHAHDJCBDECFOIIEEHLGCAMHODNEBGBEGNBAPMDKMLNAAPLGGGPBIBKPDKIDHACNILHEANBPAHHAHKENOOIPBHGMGPHFEKOIAFJCDGEIGKHFCOGKBOEFMFNB; BIGipServeriapps_webhost_mars_443.app~iapps_webhost_mars_443_pool=1418199050.20480.0000; f5avraaaaaaaaaaaaaaaa_session_=DODNABAGIJDCGFIJBPAOPFBPBLHOHHFCCOPJKDGCMJECOMLABKKMHKLJFCHNJMPLOICDCBDEFHCGHMACEGAAOMJHGOIIIFIGPFFEOBJELFDAKKFBCJIPFELKCMNMEODP; TS0151fc2b=0167a1c8619d6b5ba81debf7890eb2ec195cf167b2c1f7ede486e8f058336a773e61be0ce584235df837d4efda2cfa9106c3c86646; XSRF-TOKEN=eyJpdiI6InRRT0pnM1cvZzUxK28zQmk0R1NGTGc9PSIsInZhbHVlIjoiRElNU1dBZTV2emtkVFR3bmxET0hLSG1hN0h6cC9YU0I1Nk1hWkljSkZ4ejlrK1FqLytQZWNOOHZHMGM3WnRTdUZFRzdaV1hya3kzYnFvV1NjVDV4bHlLV3QxQ1F6TUI1Z3ZRWVdPWUdwL3E3WG54dWtQRUFtNVNEMk4rYTVDby8iLCJtYWMiOiJmYzg3ZjQ4ZGU0NTg3Zjg5ZDBmNWJhMjViNjE5ZTljNjdkMGZhMDliNjY3ZDdmZDg1YzBiZDkxNGI1YWNmOGNkIiwidGFnIjoiIn0%3D; laravel_session=eyJpdiI6IlY5bTlIWE5ONHFxT3QwY0E3aWdUU3c9PSIsInZhbHVlIjoiU3hPcWoySitnZ243OTV2RFdMSXovTnpkeWRIbHh6ZXp2MW5lS0xxVnRMRGRsemQwdVM0Ymo1b3l1OUdpUW9SbzVsdlU2aEZNbWtrQkltQ1lRMFJqcWhOY0xQcG9mQUlQN2g5RitJbGdYTi9tOG5PbHI3OHRDTTJncS9wMHZSZEUiLCJtYWMiOiIxNjE4NDY3YWNmNGM5MzVkZmZiNGJlOTQ0M2ZmMDFiY2E5ZGZhOGJlMWU2NjY5YzBkMTQ1NmNiZmUwOGUzNDc2IiwidGFnIjoiIn0%3D; TS1a53eee7027=0815dd1fcdab20006704c345a5d4485c31415c00dcb08fc4253319549874210863506028590a1a5308237cb7c6113000476e34dbb307fbfae0ac5dc88565f28b19e450fc8257984d6249c809412536ee2d1c319414c7519c54dbbf99b84ff45c';

  final http.Client _client;
  String? _csrfToken;
  String? _cookieHeader;
  String _userAgent =
      'Mozilla/5.0 (Linux; Android 16; ONEPLUS 15 Build/SKQ1.211202.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/143.0.7499.192 Mobile Safari/537.36';
  DateTime? _lastCsrfFetch;
  final Duration _csrfTtl = const Duration(minutes: 15);

  BpsGcService({http.Client? client}) : _client = client ?? http.Client();

  void setUserAgent(String ua) {
    if (ua.isNotEmpty) {
      _userAgent = ua;
    }
  }

  void setCookiesFromHeader(String cookieString) {
    _cookieHeader = cookieString;
  }

  String? get cookieHeader => _cookieHeader;

  Future<void> autoGetCsrfToken() async {
    final url = Uri.parse('$baseUrl/dirgc');
    final response = await _client.get(
      url,
      headers: {
        'User-Agent': _userAgent,
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
        'X-Requested-With': 'XMLHttpRequest',
        'sec-ch-ua':
            '"Android WebView";v="143", "Chromium";v="143", "Not A(Brand";v="24"',
        'sec-ch-ua-mobile': '?1',
        'sec-ch-ua-platform': '"Android"',
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

  String? _manualGcToken;
  String? _manualCsrfToken;

  void setTokens(String gcToken, String csrfToken) {
    _manualGcToken = gcToken;
    _manualCsrfToken = csrfToken;
    _csrfToken = csrfToken; // update the auto one too just in case
  }

  Future<Map<String, dynamic>?> konfirmasiUser({
    required String perusahaanId,
    required String latitude,
    required String longitude,
    required String hasilGc,
    required String
    gcToken, // This argument is passed from caller, usually via provider/bloc
  }) async {
    // Use manual tokens if available, otherwise use passed argument or forced
    final effectiveGcToken = _manualGcToken ?? gcToken;
    final effectiveCsrfToken =
        _manualCsrfToken ?? _forcedToken; // Default to forced if no manual

    debugPrint(
      'BpsGcService.konfirmasiUser payload => perusahaanId=$perusahaanId, '
      'hasilGc=$hasilGc, lat="$latitude", lon="$longitude"',
    );

    // Ensure we have fresh CSRF if we don't have a manual one
    if (_manualCsrfToken == null) {
      _cookieHeader = _forcedCookie;
      await _ensureFreshCsrf();
    }

    // If we have manual cookie, use it
    // _cookieHeader is already set via setCookiesFromHeader

    final url = Uri.parse('$baseUrl/dirgc/konfirmasi-user');

    final body = {
      'perusahaan_id': perusahaanId,
      'latitude': latitude,
      'longitude': longitude,
      'hasilgc': hasilGc,
      'gc_token': effectiveGcToken.isNotEmpty
          ? effectiveGcToken
          : _forcedGcToken,
      '_token': effectiveCsrfToken.isNotEmpty
          ? effectiveCsrfToken
          : (_csrfToken ?? _forcedToken),
    };

    final response = await _client.post(
      url,
      headers: {
        'User-Agent': _userAgent, // Use Mobile UA
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'X-Requested-With': 'XMLHttpRequest',
        'sec-ch-ua':
            '"Android WebView";v="143", "Chromium";v="143", "Not A(Brand";v="24"',
        'sec-ch-ua-mobile': '?1',
        'sec-ch-ua-platform': '"Android"',
        'Cookie': _cookieHeader ?? '',
      },
      body: body,
    );

    _mergeSetCookie(response.headers);

    if (response.statusCode != 200) {
      debugPrint(
        'BpsGcService.konfirmasiUser status=${response.statusCode}, '
        'body=${response.body}',
      );
      await autoGetCsrfToken();
      final retry = await _client.post(
        url,
        headers: {
          'User-Agent': _userAgent,
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'X-Requested-With': 'XMLHttpRequest',
          'sec-ch-ua':
              '"Android WebView";v="143", "Chromium";v="143", "Not A(Brand";v="24"',
          'sec-ch-ua-mobile': '?1',
          'sec-ch-ua-platform': '"Android"',
          'Cookie': _cookieHeader ?? '',
        },
        body: {...body, '_token': _forcedToken},
      );
      _mergeSetCookie(retry.headers);
      if (retry.statusCode != 200) return null;
      final rb = retry.body;
      if (_looksLikeLoginPage(rb)) return null;
      return jsonDecode(rb) as Map<String, dynamic>;
    }

    final respBody = response.body;
    if (_looksLikeLoginPage(respBody)) {
      return null;
    }

    return jsonDecode(respBody) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> debugFetchGcCard({
    int start = 0,
    int length = 10,
    String namaUsaha = '',
    String alamatUsaha = '',
    String provinsi = '132',
    String kabupaten = '2582',
    String kecamatan = '',
    String desa = '',
    String statusFilter = 'semua',
    String sumberData = '',
    String skalaUsaha = '',
    String idsbr = '',
    String historyProfiling = '',
    String fLatlong = '',
    String fGc = '',
  }) async {
    _cookieHeader = _forcedCookie;
    final url = Uri.parse('$baseUrl/direktori-usaha/data-gc-card');
    final body = {
      '_token': _forcedToken,
      'start': start.toString(),
      'length': length.toString(),
      'nama_usaha': namaUsaha,
      'alamat_usaha': alamatUsaha,
      'provinsi': provinsi,
      'kabupaten': kabupaten,
      'kecamatan': kecamatan,
      'desa': desa,
      'status_filter': statusFilter,
      'rtotal': '0',
      'sumber_data': sumberData,
      'skala_usaha': skalaUsaha,
      'idsbr': idsbr,
      'history_profiling': historyProfiling,
      'f_latlong': fLatlong,
      'f_gc': fGc,
    };
    debugPrint('BpsGcService.debugFetchGcCard body => ${jsonEncode(body)}');
    final response = await _client.post(
      url,
      headers: {
        'User-Agent': _userAgent,
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'X-Requested-With': 'XMLHttpRequest',
        'sec-ch-ua':
            '"Android WebView";v="143", "Chromium";v="143", "Not A(Brand";v="24"',
        'sec-ch-ua-mobile': '?1',
        'sec-ch-ua-platform': '"Android"',
        'Cookie': _cookieHeader ?? '',
      },
      body: body,
    );
    debugPrint('BpsGcService.debugFetchGcCard status=${response.statusCode}');
    if (response.statusCode != 200) {
      debugPrint('BpsGcService.debugFetchGcCard body=${response.body}');
      return null;
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
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
          'User-Agent': _userAgent,
          'Accept': '*/*',
          'Accept-Language': 'en-US,en;q=0.9',
          'X-Requested-With': 'XMLHttpRequest',
          'sec-ch-ua':
              '"Android WebView";v="143", "Chromium";v="143", "Not A(Brand";v="24"',
          'sec-ch-ua-mobile': '?1',
          'sec-ch-ua-platform': '"Android"',
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
