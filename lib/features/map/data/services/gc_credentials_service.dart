import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/supabase_config.dart';

class GcCredentialsService {
  final SupabaseClient _client = SupabaseConfig.client;

  Future<Map<String, String>?> loadGlobal() async {
    try {
      final row = await _client
          .from('gc_credentials_global')
          .select()
          .eq('key', 'global')
          .maybeSingle();
      if (row == null) return null;
      final cookie = row['gc_cookie'] as String? ?? '';
      final token = row['gc_token'] as String? ?? '';
      return {'gc_cookie': cookie, 'gc_token': token};
    } catch (_) {
      return null;
    }
  }

  Future<bool> upsertGlobal({String? gcCookie, String? gcToken}) async {
    try {
      final payload = {
        'key': 'global',
        if (gcCookie != null) 'gc_cookie': gcCookie,
        if (gcToken != null) 'gc_token': gcToken,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await _client
          .from('gc_credentials_global')
          .upsert(payload, onConflict: 'key');
      return true;
    } catch (_) {
      return false;
    }
  }
}
