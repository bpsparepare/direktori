import '../../domain/entities/contribution_summary.dart';
import '../../domain/entities/leaderboard_entry.dart';

/// Model untuk ContributionSummary yang menangani serialisasi JSON
class ContributionSummaryModel extends ContributionSummary {
  const ContributionSummaryModel({
    required super.userId,
    required super.userName,
    required super.totalContributions,
    required super.totalPoints,
    required super.currentLevel,
    required super.levelName,
    required super.rank,
    required super.contributionsByType,
    super.lastContributionDate,
  });

  /// Factory constructor dari JSON
  factory ContributionSummaryModel.fromJson(Map<String, dynamic> json) {
    return ContributionSummaryModel(
      userId: json['user_id'] as String,
      userName: json['user_name'] as String,
      totalContributions: json['total_contributions'] as int,
      totalPoints: json['total_points'] as int,
      currentLevel: json['current_level'] as int,
      levelName: json['level_name'] as String,
      rank: json['rank'] as int,
      contributionsByType: Map<String, int>.from(
        json['contributions_by_type'] as Map<String, dynamic>,
      ),
      lastContributionDate: json['last_contribution_date'] != null
          ? DateTime.parse(json['last_contribution_date'] as String)
          : null,
    );
  }

  /// Convert ke JSON
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'user_name': userName,
      'total_contributions': totalContributions,
      'total_points': totalPoints,
      'current_level': currentLevel,
      'level_name': levelName,
      'rank': rank,
      'contributions_by_type': contributionsByType,
      'last_contribution_date': lastContributionDate?.toIso8601String(),
    };
  }

  /// Factory constructor dari Entity
  factory ContributionSummaryModel.fromEntity(ContributionSummary entity) {
    return ContributionSummaryModel(
      userId: entity.userId,
      userName: entity.userName,
      totalContributions: entity.totalContributions,
      totalPoints: entity.totalPoints,
      currentLevel: entity.currentLevel,
      levelName: entity.levelName,
      rank: entity.rank,
      contributionsByType: entity.contributionsByType,
      lastContributionDate: entity.lastContributionDate,
    );
  }

  /// Convert ke Entity
  ContributionSummary toEntity() {
    return ContributionSummary(
      userId: userId,
      userName: userName,
      totalContributions: totalContributions,
      totalPoints: totalPoints,
      currentLevel: currentLevel,
      levelName: levelName,
      rank: rank,
      contributionsByType: contributionsByType,
      lastContributionDate: lastContributionDate,
    );
  }
}

/// Model untuk LeaderboardEntry yang menangani serialisasi JSON
class LeaderboardEntryModel extends LeaderboardEntry {
  const LeaderboardEntryModel({
    required super.userId,
    required super.userName,
    super.userAvatar,
    required super.totalPoints,
    required super.totalContributions,
    required super.level,
    required super.rank,
    required super.period,
    required super.lastContribution,
  });

  /// Factory constructor dari JSON
  factory LeaderboardEntryModel.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntryModel(
      userId: json['user_id'] as String,
      userName: json['user_name'] as String,
      userAvatar: json['user_avatar'] as String?,
      totalPoints: json['total_points'] as int,
      totalContributions: json['total_contributions'] as int,
      level: json['level'] as int,
      rank: json['rank'] as int,
      period: json['period'] as String? ?? 'monthly',
      lastContribution: DateTime.parse(json['last_contribution'] as String),
    );
  }

  /// Convert ke JSON
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'user_name': userName,
      'user_avatar': userAvatar,
      'total_points': totalPoints,
      'total_contributions': totalContributions,
      'level': level,
      'rank': rank,
      'period': period,
      'last_contribution': lastContribution.toIso8601String(),
    };
  }

  /// Factory constructor dari Entity
  factory LeaderboardEntryModel.fromEntity(LeaderboardEntry entity) {
    return LeaderboardEntryModel(
      userId: entity.userId,
      userName: entity.userName,
      userAvatar: entity.userAvatar,
      totalPoints: entity.totalPoints,
      totalContributions: entity.totalContributions,
      level: entity.level,
      rank: entity.rank,
      period: entity.period,
      lastContribution: entity.lastContribution,
    );
  }

  /// Convert ke Entity
  LeaderboardEntry toEntity() {
    return LeaderboardEntry(
      userId: userId,
      userName: userName,
      userAvatar: userAvatar,
      totalPoints: totalPoints,
      totalContributions: totalContributions,
      level: level,
      rank: rank,
      period: period,
      lastContribution: lastContribution,
    );
  }
}
