import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/supabase_config.dart';
import '../models/user_contribution_model.dart';
import '../models/user_stats_model.dart';
import '../models/contribution_summary_model.dart';

/// Abstract class untuk remote data source kontribusi
abstract class ContributionRemoteDataSource {
  /// Mendapatkan ID pengguna yang sedang login
  String? getCurrentUserId();
  Future<UserContributionModel> createContribution(
    UserContributionModel contribution,
  );
  Future<List<UserContributionModel>> getUserContributions(
    String userId, {
    int? limit,
    int? offset,
  });
  Future<UserContributionModel> updateContribution(
    String id,
    Map<String, dynamic> updates,
  );
  Future<UserStatsModel?> getUserStats(String userId);
  Future<ContributionSummaryModel?> getUserContributionSummary(String userId);
  Future<List<LeaderboardEntryModel>> getLeaderboard({
    int limit = 10,
    int offset = 0,
  });
  Future<Map<String, dynamic>> getContributionAnalytics(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
  });
}

/// Implementasi remote data source menggunakan Supabase
class ContributionRemoteDataSourceImpl implements ContributionRemoteDataSource {
  final SupabaseClient _supabaseClient;

  ContributionRemoteDataSourceImpl({required SupabaseClient supabaseClient})
    : _supabaseClient = supabaseClient;

  @override
  String? getCurrentUserId() {
    return _supabaseClient.auth.currentUser?.id;
  }

  @override
  Future<UserContributionModel> createContribution(
    UserContributionModel contribution,
  ) async {
    try {
      print('🗄️ [DATASOURCE] Menyimpan kontribusi ke Supabase...');
      print('📊 [DATASOURCE] Data: ${contribution.toJson()}');

      final response = await _supabaseClient
          .from('direktori_user_contributions')
          .insert(contribution.toJson())
          .select()
          .single();

      print('✅ [DATASOURCE] Kontribusi berhasil disimpan ke database');
      print('📋 [DATASOURCE] Response: $response');

      return UserContributionModel.fromJson(response);
    } catch (e) {
      print('❌ [DATASOURCE] Gagal menyimpan kontribusi: $e');
      throw Exception('Failed to create contribution: $e');
    }
  }

  @override
  Future<List<UserContributionModel>> getUserContributions(
    String userId, {
    int? limit,
    int? offset,
  }) async {
    try {
      print('🔍 [DATASOURCE] Mengambil kontribusi dari Supabase...');
      print('👤 [DATASOURCE] User ID: $userId');
      print('📊 [DATASOURCE] Limit: $limit, Offset: $offset');

      var query = _supabaseClient
          .from('direktori_user_contributions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (limit != null) {
        query = query.limit(limit);
      }

      if (offset != null) {
        query = query.range(offset, offset + (limit ?? 10) - 1);
      }

      final response = await query;
      print(
        '📋 [DATASOURCE] Response dari database: ${response.length} records',
      );
      print(
        '🔍 [DATASOURCE] Sample data: ${response.isNotEmpty ? response.first : 'No data'}',
      );

      return response
          .map((json) => UserContributionModel.fromJson(json))
          .toList();
    } catch (e) {
      print('❌ [DATASOURCE] Gagal mengambil kontribusi: $e');
      throw Exception('Failed to get user contributions: $e');
    }
  }

  @override
  Future<UserContributionModel> updateContribution(
    String id,
    Map<String, dynamic> updates,
  ) async {
    try {
      final response = await _supabaseClient
          .from('direktori_user_contributions')
          .update(updates)
          .eq('id', id)
          .select()
          .single();

      return UserContributionModel.fromJson(response);
    } catch (e) {
      throw Exception('Failed to update contribution: $e');
    }
  }

  @override
  Future<UserStatsModel?> getUserStats(String userId) async {
    try {
      final response = await _supabaseClient
          .from('direktori_user_stats')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) return null;

      return UserStatsModel.fromJson(response);
    } catch (e) {
      throw Exception('Failed to get user stats: $e');
    }
  }

  @override
  Future<ContributionSummaryModel?> getUserContributionSummary(
    String userId,
  ) async {
    try {
      // Menggunakan RPC function yang dibuat di database
      final response = await _supabaseClient.rpc(
        'get_user_contribution_summary',
        params: {'p_user_id': userId},
      );

      if (response == null) return null;

      return ContributionSummaryModel.fromJson(response);
    } catch (e) {
      throw Exception('Failed to get user contribution summary: $e');
    }
  }

  @override
  Future<List<LeaderboardEntryModel>> getLeaderboard({
    int limit = 10,
    int offset = 0,
  }) async {
    try {
      // Menggunakan RPC function untuk leaderboard
      final response = await _supabaseClient.rpc(
        'get_leaderboard',
        params: {'p_limit': limit, 'p_offset': offset},
      );

      return response
          .map<LeaderboardEntryModel>(
            (json) => LeaderboardEntryModel.fromJson(json),
          )
          .toList();
    } catch (e) {
      throw Exception('Failed to get leaderboard: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> getContributionAnalytics(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // Menggunakan RPC function untuk analytics
      final response = await _supabaseClient.rpc(
        'get_contribution_analytics',
        params: {
          'p_user_id': userId,
          'p_start_date': startDate?.toIso8601String(),
          'p_end_date': endDate?.toIso8601String(),
        },
      );

      return response as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to get contribution analytics: $e');
    }
  }

  /// Helper method untuk check apakah user sudah login
  bool get isUserLoggedIn => _supabaseClient.auth.currentUser != null;
}
