import 'package:equatable/equatable.dart';

/// Entity untuk ringkasan kontribusi pengguna
class ContributionSummary extends Equatable {
  final String userId;
  final String? userName;
  final String? userEmail;
  final int totalContributions;
  final int totalPoints;
  final int currentLevel;
  final String levelName;
  final int rank;
  final Map<String, int> contributionsByType;
  final DateTime? lastContributionDate;

  const ContributionSummary({
    required this.userId,
    this.userName,
    this.userEmail,
    required this.totalContributions,
    required this.totalPoints,
    required this.currentLevel,
    required this.levelName,
    required this.rank,
    required this.contributionsByType,
    this.lastContributionDate,
  });

  @override
  List<Object?> get props => [
        userId,
        userName,
        userEmail,
        totalContributions,
        totalPoints,
        currentLevel,
        levelName,
        rank,
        contributionsByType,
        lastContributionDate,
      ];

  ContributionSummary copyWith({
    String? userId,
    String? userName,
    String? userEmail,
    int? totalContributions,
    int? totalPoints,
    int? currentLevel,
    String? levelName,
    int? rank,
    Map<String, int>? contributionsByType,
    DateTime? lastContributionDate,
  }) {
    return ContributionSummary(
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
      totalContributions: totalContributions ?? this.totalContributions,
      totalPoints: totalPoints ?? this.totalPoints,
      currentLevel: currentLevel ?? this.currentLevel,
      levelName: levelName ?? this.levelName,
      rank: rank ?? this.rank,
      contributionsByType: contributionsByType ?? this.contributionsByType,
      lastContributionDate: lastContributionDate ?? this.lastContributionDate,
    );
  }
}