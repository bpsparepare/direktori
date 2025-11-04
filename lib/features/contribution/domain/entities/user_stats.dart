import 'package:equatable/equatable.dart';

/// Entity yang merepresentasikan statistik kontribusi pengguna
class UserStats extends Equatable {
  final String userId;
  final int totalContributions;
  final int totalPoints;
  final int currentLevel;
  final double levelProgress;
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastContributionDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserStats({
    required this.userId,
    required this.totalContributions,
    required this.totalPoints,
    required this.currentLevel,
    required this.levelProgress,
    required this.currentStreak,
    required this.longestStreak,
    this.lastContributionDate,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
    userId,
    totalContributions,
    totalPoints,
    currentLevel,
    levelProgress,
    currentStreak,
    longestStreak,
    lastContributionDate,
    createdAt,
    updatedAt,
  ];

  UserStats copyWith({
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
    return UserStats(
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

  /// Menghitung level berdasarkan total poin
  static int calculateLevel(int totalPoints) {
    if (totalPoints < 100) return 1;
    if (totalPoints < 250) return 2;
    if (totalPoints < 500) return 3;
    if (totalPoints < 1000) return 4;
    if (totalPoints < 2000) return 5;
    if (totalPoints < 5000) return 6;
    if (totalPoints < 10000) return 7;
    if (totalPoints < 20000) return 8;
    if (totalPoints < 50000) return 9;
    return 10; // Level maksimum
  }

  /// Menghitung progress level (0.0 - 1.0)
  static double calculateLevelProgress(int totalPoints) {
    final currentLevel = calculateLevel(totalPoints);
    final currentLevelMinPoints = _getLevelMinPoints(currentLevel);
    final nextLevelMinPoints = _getLevelMinPoints(currentLevel + 1);

    if (currentLevel >= 10) return 1.0; // Level maksimum

    final pointsInCurrentLevel = totalPoints - currentLevelMinPoints;
    final pointsNeededForNextLevel = nextLevelMinPoints - currentLevelMinPoints;

    return pointsInCurrentLevel / pointsNeededForNextLevel;
  }

  /// Mendapatkan poin minimum untuk level tertentu
  static int _getLevelMinPoints(int level) {
    switch (level) {
      case 1:
        return 0;
      case 2:
        return 100;
      case 3:
        return 250;
      case 4:
        return 500;
      case 5:
        return 1000;
      case 6:
        return 2000;
      case 7:
        return 5000;
      case 8:
        return 10000;
      case 9:
        return 20000;
      case 10:
        return 50000;
      default:
        return 50000; // Level maksimum
    }
  }

  /// Mendapatkan nama level
  String get levelName {
    switch (currentLevel) {
      case 1:
        return 'Pemula';
      case 2:
        return 'Kontributor';
      case 3:
        return 'Aktif';
      case 4:
        return 'Berpengalaman';
      case 5:
        return 'Ahli';
      case 6:
        return 'Master';
      case 7:
        return 'Veteran';
      case 8:
        return 'Elite';
      case 9:
        return 'Champion';
      case 10:
        return 'Legend';
      default:
        return 'Unknown';
    }
  }

  /// Mendapatkan poin yang dibutuhkan untuk level berikutnya
  int get pointsToNextLevel {
    if (currentLevel >= 10) return 0;
    final nextLevelMinPoints = _getLevelMinPoints(currentLevel + 1);
    return nextLevelMinPoints - totalPoints;
  }
}
