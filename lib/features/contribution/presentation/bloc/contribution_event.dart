import 'package:equatable/equatable.dart';

/// Base class untuk semua contribution events
abstract class ContributionEvent extends Equatable {
  const ContributionEvent();

  @override
  List<Object?> get props => [];
}

// === User Contributions Events ===

/// Event untuk membuat kontribusi baru
class CreateContributionEvent extends ContributionEvent {
  final String actionType;
  final String targetType;
  final String targetId;
  final Map<String, dynamic>? changes;
  final double? latitude;
  final double? longitude;

  const CreateContributionEvent({
    required this.actionType,
    required this.targetType,
    required this.targetId,
    this.changes,
    this.latitude,
    this.longitude,
  });

  @override
  List<Object?> get props => [
        actionType,
        targetType,
        targetId,
        changes,
        latitude,
        longitude,
      ];
}

/// Event untuk mendapatkan kontribusi pengguna
class GetUserContributionsEvent extends ContributionEvent {
  final String? userId;
  final int? limit;
  final int? offset;
  final String? status;

  const GetUserContributionsEvent({
    this.userId,
    this.limit,
    this.offset,
    this.status,
  });

  @override
  List<Object?> get props => [userId, limit, offset, status];
}

/// Event untuk update status kontribusi
class UpdateContributionStatusEvent extends ContributionEvent {
  final String contributionId;
  final String status;

  const UpdateContributionStatusEvent({
    required this.contributionId,
    required this.status,
  });

  @override
  List<Object?> get props => [contributionId, status];
}

// === User Stats Events ===

/// Event untuk mendapatkan statistik pengguna
class GetUserStatsEvent extends ContributionEvent {
  final String? userId;

  const GetUserStatsEvent({this.userId});

  @override
  List<Object?> get props => [userId];
}

/// Event untuk refresh statistik pengguna
class RefreshUserStatsEvent extends ContributionEvent {
  final String? userId;

  const RefreshUserStatsEvent({this.userId});

  @override
  List<Object?> get props => [userId];
}

// === Leaderboard Events ===

/// Event untuk mendapatkan leaderboard
class GetLeaderboardEvent extends ContributionEvent {
  final int limit;
  final int offset;
  final String period;

  const GetLeaderboardEvent({
    this.limit = 10,
    this.offset = 0,
    this.period = 'monthly',
  });

  @override
  List<Object?> get props => [limit, offset, period];
}

/// Event untuk mendapatkan ranking pengguna
class GetUserRankEvent extends ContributionEvent {
  final String? userId;

  const GetUserRankEvent({this.userId});

  @override
  List<Object?> get props => [userId];
}

// === Analytics Events ===

/// Event untuk mendapatkan statistik kontribusi
class GetContributionStatsEvent extends ContributionEvent {
  final String? userId;
  final DateTime? startDate;
  final DateTime? endDate;

  const GetContributionStatsEvent({
    this.userId,
    this.startDate,
    this.endDate,
  });

  @override
  List<Object?> get props => [userId, startDate, endDate];
}

/// Event untuk mendapatkan kontribusi terbaru
class GetRecentContributionsEvent extends ContributionEvent {
  final int limit;
  final String? actionType;

  const GetRecentContributionsEvent({
    this.limit = 10,
    this.actionType,
  });

  @override
  List<Object?> get props => [limit, actionType];
}

// === General Events ===

/// Event untuk reset state
class ResetContributionStateEvent extends ContributionEvent {
  const ResetContributionStateEvent();
}

/// Event untuk refresh semua data
class RefreshAllContributionDataEvent extends ContributionEvent {
  const RefreshAllContributionDataEvent();
}