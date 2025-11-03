import '../../domain/entities/user_stats.dart';

/// Model untuk UserStats yang menangani serialisasi JSON
class UserStatsModel extends UserStats {
  const UserStatsModel({
    required super.userId,
    required super.totalContributions,
    required super.totalPoints,
    required super.currentLevel,
    required super.levelProgress,
    required super.currentStreak,
    required super.longestStreak,
    super.lastContributionDate,
    required super.createdAt,
    required super.updatedAt,
  });

  /// Factory constructor dari JSON
  factory UserStatsModel.fromJson(Map<String, dynamic> json) {
    return UserStatsModel(
      userId: json['user_id'] as String,
      totalContributions: json['total_contributions'] as int,
      totalPoints: json['total_points'] as int,
      currentLevel: json['current_level'] as int,
      levelProgress: (json['level_progress'] as num).toDouble(),
      currentStreak: json['current_streak'] as int,
      longestStreak: json['longest_streak'] as int,
      lastContributionDate: json['last_contribution_date'] != null
          ? DateTime.parse(json['last_contribution_date'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert ke JSON
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'total_contributions': totalContributions,
      'total_points': totalPoints,
      'current_level': currentLevel,
      'level_progress': levelProgress,
      'current_streak': currentStreak,
      'longest_streak': longestStreak,
      'last_contribution_date': lastContributionDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Factory constructor dari Entity
  factory UserStatsModel.fromEntity(UserStats entity) {
    return UserStatsModel(
      userId: entity.userId,
      totalContributions: entity.totalContributions,
      totalPoints: entity.totalPoints,
      currentLevel: entity.currentLevel,
      levelProgress: entity.levelProgress,
      currentStreak: entity.currentStreak,
      longestStreak: entity.longestStreak,
      lastContributionDate: entity.lastContributionDate,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }

  /// Convert ke Entity
  UserStats toEntity() {
    return UserStats(
      userId: userId,
      totalContributions: totalContributions,
      totalPoints: totalPoints,
      currentLevel: currentLevel,
      levelProgress: levelProgress,
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      lastContributionDate: lastContributionDate,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Copy with method untuk model
  UserStatsModel copyWithModel({
    String? userId,
    int? totalContributions,
    int? totalPoints,
    int? currentLevel,
    double? levelProgress,
    int? currentStreak,
    int? longestStreak,
    DateTime? lastContributionDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserStatsModel(
      userId: userId ?? this.userId,
      totalContributions: totalContributions ?? this.totalContributions,
      totalPoints: totalPoints ?? this.totalPoints,
      currentLevel: currentLevel ?? this.currentLevel,
      levelProgress: levelProgress ?? this.levelProgress,
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      lastContributionDate: lastContributionDate ?? this.lastContributionDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}