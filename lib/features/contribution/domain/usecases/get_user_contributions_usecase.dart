import '../entities/user_contribution.dart';
import '../repositories/contribution_repository.dart';

/// Use case untuk mendapatkan daftar kontribusi pengguna
class GetUserContributionsUseCase {
  final ContributionRepository repository;

  GetUserContributionsUseCase(this.repository);

  Future<List<UserContribution>> call({
    required String userId,
    int? limit,
    int? offset,
    String? status,
  }) async {
    return await repository.getUserContributions(
      userId: userId,
      limit: limit,
      offset: offset,
      status: status,
    );
  }
}