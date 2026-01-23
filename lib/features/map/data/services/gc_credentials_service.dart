import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/supabase_config.dart';

class GcCredentialsService {
  final SupabaseClient _client = SupabaseConfig.client;

  // Global credentials methods removed as credentials are now strictly local/session-based.
}
