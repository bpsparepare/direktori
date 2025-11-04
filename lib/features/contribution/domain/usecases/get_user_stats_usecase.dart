import '../entities/user_stats.dart';
import '../repositories/contribution_repository.dart';

/// Use case untuk mendapatkan statistik pengguna
class GetUserStatsUseCase {
  final ContributionRepository repository;

  GetUserStatsUseCase(this.repository);

  Future<UserStats?> call(String userId) async {
    return await repository.getUserStats(userId);
  }
}
