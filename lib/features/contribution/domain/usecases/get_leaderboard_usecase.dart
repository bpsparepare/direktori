import '../entities/contribution_summary.dart';
import '../entities/leaderboard_entry.dart';
import '../repositories/contribution_repository.dart';

/// Use case untuk mendapatkan leaderboard
class GetLeaderboardUseCase {
  final ContributionRepository repository;

  GetLeaderboardUseCase(this.repository);

  Future<List<LeaderboardEntry>> call({
    int limit = 10,
    int offset = 0,
  }) async {
    return await repository.getLeaderboard(
      limit: limit,
      offset: offset,
    );
  }
}