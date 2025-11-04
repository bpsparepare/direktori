/// Entity untuk entri leaderboard kontributor
class LeaderboardEntry {
  final String userId;
  final String userName;
  final String? userAvatar;
  final int totalPoints;
  final int totalContributions;
  final int level;
  final int rank;
  final String period;
  final DateTime lastContribution;

  const LeaderboardEntry({
    required this.userId,
    required this.userName,
    this.userAvatar,
    required this.totalPoints,
    required this.totalContributions,
    required this.level,
    required this.rank,
    required this.period,
    required this.lastContribution,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is LeaderboardEntry &&
        other.userId == userId &&
        other.userName == userName &&
        other.userAvatar == userAvatar &&
        other.totalPoints == totalPoints &&
        other.totalContributions == totalContributions &&
        other.level == level &&
        other.rank == rank &&
        other.period == period &&
        other.lastContribution == lastContribution;
  }

  @override
  int get hashCode {
    return userId.hashCode ^
        userName.hashCode ^
        userAvatar.hashCode ^
        totalPoints.hashCode ^
        totalContributions.hashCode ^
        level.hashCode ^
        rank.hashCode ^
        period.hashCode ^
        lastContribution.hashCode;
  }

  @override
  String toString() {
    return 'LeaderboardEntry(userId: $userId, userName: $userName, userAvatar: $userAvatar, totalPoints: $totalPoints, totalContributions: $totalContributions, level: $level, rank: $rank, period: $period, lastContribution: $lastContribution)';
  }
}
