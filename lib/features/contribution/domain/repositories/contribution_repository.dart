import '../entities/user_contribution.dart';
import '../entities/user_stats.dart';
import '../entities/contribution_summary.dart';
import '../entities/leaderboard_entry.dart';

/// Repository interface untuk mengelola data kontribusi
abstract class ContributionRepository {
  /// Mendapatkan ID pengguna yang sedang login
  String? getCurrentUserId();
  // === User Contributions ===
  
  /// Membuat kontribusi baru
  Future<UserContribution> createContribution({
    required String userId,
    required String actionType,
    required String targetType,
    required String targetId,
    Map<String, dynamic>? changes,
    double? latitude,
    double? longitude,
  });

  /// Mendapatkan daftar kontribusi pengguna
  Future<List<UserContribution>> getUserContributions({
    required String userId,
    int? limit,
    int? offset,
    String? status,
  });

  /// Mendapatkan kontribusi berdasarkan ID
  Future<UserContribution?> getContributionById(String contributionId);

  /// Update status kontribusi
  Future<bool> updateContributionStatus({
    required String contributionId,
    required String status,
  });

  // === User Stats ===
  
  /// Mendapatkan statistik pengguna
  Future<UserStats?> getUserStats(String userId);

  /// Update statistik pengguna (biasanya dipanggil otomatis oleh trigger)
  Future<bool> updateUserStats(String userId);

  // === Contribution Summary & Leaderboard ===
  
  /// Mendapatkan ringkasan kontribusi pengguna
  Future<ContributionSummary?> getContributionSummary(String userId);

  /// Mendapatkan leaderboard
  Future<List<LeaderboardEntry>> getLeaderboard({
    int limit = 10,
    int offset = 0,
  });

  /// Mendapatkan ranking pengguna
  Future<int> getUserRank(String userId);

  // === Analytics ===
  
  /// Mendapatkan statistik kontribusi per periode
  Future<Map<String, int>> getContributionStats({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Mendapatkan kontribusi terbaru
  Future<List<UserContribution>> getRecentContributions({
    int limit = 10,
    String? actionType,
  });
}