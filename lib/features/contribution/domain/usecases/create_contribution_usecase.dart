import '../entities/user_contribution.dart';
import '../repositories/contribution_repository.dart';

/// Use case untuk membuat kontribusi baru
class CreateContributionUseCase {
  final ContributionRepository repository;

  CreateContributionUseCase(this.repository);

  Future<UserContribution> call({
    required String userId,
    required String actionType,
    required String targetType,
    required String targetId,
    Map<String, dynamic>? changes,
    double? latitude,
    double? longitude,
    String? operationId,
  }) async {
    return await repository.createContribution(
      userId: userId,
      actionType: actionType,
      targetType: targetType,
      targetId: targetId,
      changes: changes,
      latitude: latitude,
      longitude: longitude,
      operationId: operationId,
    );
  }
}
