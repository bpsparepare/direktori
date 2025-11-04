import 'package:equatable/equatable.dart';
import '../../domain/entities/user_contribution.dart';
import '../../domain/entities/user_stats.dart';
import '../../domain/entities/contribution_summary.dart';
import '../../domain/entities/leaderboard_entry.dart';

/// Base class untuk semua contribution states
abstract class ContributionState extends Equatable {
  const ContributionState();

  @override
  List<Object?> get props => [];
}

/// Initial state
class ContributionInitial extends ContributionState {
  const ContributionInitial();
}

/// Loading state
class ContributionLoading extends ContributionState {
  const ContributionLoading();
}

/// State ketika berhasil memuat data
class ContributionLoaded extends ContributionState {
  final List<UserContribution> contributions;
  final UserStats? userStats;
  final List<LeaderboardEntry> leaderboard;
  final Map<String, int> contributionStats;
  final int? userRank;
  final bool isCreatingContribution;
  final bool isUpdatingStatus;

  const ContributionLoaded({
    this.contributions = const [],
    this.userStats,
    this.leaderboard = const [],
    this.contributionStats = const {},
    this.userRank,
    this.isCreatingContribution = false,
    this.isUpdatingStatus = false,
  });

  ContributionLoaded copyWith({
    List<UserContribution>? contributions,
    UserStats? userStats,
    List<LeaderboardEntry>? leaderboard,
    Map<String, int>? contributionStats,
    int? userRank,
    bool? isCreatingContribution,
    bool? isUpdatingStatus,
  }) {
    return ContributionLoaded(
      contributions: contributions ?? this.contributions,
      userStats: userStats ?? this.userStats,
      leaderboard: leaderboard ?? this.leaderboard,
      contributionStats: contributionStats ?? this.contributionStats,
      userRank: userRank ?? this.userRank,
      isCreatingContribution:
          isCreatingContribution ?? this.isCreatingContribution,
      isUpdatingStatus: isUpdatingStatus ?? this.isUpdatingStatus,
    );
  }

  @override
  List<Object?> get props => [
    contributions,
    userStats,
    leaderboard,
    contributionStats,
    userRank,
    isCreatingContribution,
    isUpdatingStatus,
  ];
}

/// State ketika berhasil membuat kontribusi
class ContributionCreated extends ContributionState {
  final UserContribution contribution;

  const ContributionCreated({required this.contribution});

  @override
  List<Object?> get props => [contribution];
}

/// State ketika berhasil update status kontribusi
class ContributionStatusUpdated extends ContributionState {
  final String contributionId;
  final String newStatus;

  const ContributionStatusUpdated({
    required this.contributionId,
    required this.newStatus,
  });

  @override
  List<Object?> get props => [contributionId, newStatus];
}

/// State ketika berhasil memuat user stats
class UserStatsLoaded extends ContributionState {
  final UserStats userStats;

  const UserStatsLoaded({required this.userStats});

  @override
  List<Object?> get props => [userStats];
}

/// State ketika berhasil memuat leaderboard
class LeaderboardLoaded extends ContributionState {
  final List<LeaderboardEntry> leaderboard;
  final String period;

  const LeaderboardLoaded({required this.leaderboard, this.period = 'monthly'});

  @override
  List<Object?> get props => [leaderboard, period];
}

/// State ketika berhasil memuat contribution stats
class ContributionStatsLoaded extends ContributionState {
  final Map<String, int> stats;

  const ContributionStatsLoaded({required this.stats});

  @override
  List<Object?> get props => [stats];
}

/// State ketika berhasil memuat user rank
class UserRankLoaded extends ContributionState {
  final int rank;

  const UserRankLoaded({required this.rank});

  @override
  List<Object?> get props => [rank];
}

/// Error state
class ContributionError extends ContributionState {
  final String message;
  final String? errorCode;

  const ContributionError({required this.message, this.errorCode});

  @override
  List<Object?> get props => [message, errorCode];
}

/// State untuk operasi yang sedang berlangsung
class ContributionOperationInProgress extends ContributionState {
  final String operation;
  final String? message;

  const ContributionOperationInProgress({
    required this.operation,
    this.message,
  });

  @override
  List<Object?> get props => [operation, message];
}

/// State ketika tidak ada data
class ContributionEmpty extends ContributionState {
  final String message;

  const ContributionEmpty({this.message = 'Belum ada kontribusi'});

  @override
  List<Object?> get props => [message];
}
