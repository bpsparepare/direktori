import 'package:equatable/equatable.dart';
import '../../data/services/groundcheck_supabase_service.dart';
import '../../domain/entities/groundcheck_record.dart';
import '../pages/groundcheck_page.dart'; // For GroundcheckRecord

abstract class GroundcheckHistoryState extends Equatable {
  const GroundcheckHistoryState();

  @override
  List<Object?> get props => [];
}

class GroundcheckHistoryInitial extends GroundcheckHistoryState {}

class GroundcheckHistoryLoading extends GroundcheckHistoryState {}

class GroundcheckHistoryLoaded extends GroundcheckHistoryState {
  final List<GroundcheckRecord> records;
  final int totalCount;
  final List<Map<String, dynamic>> leaderboard;

  const GroundcheckHistoryLoaded({
    required this.records,
    required this.totalCount,
    this.leaderboard = const [],
  });

  @override
  List<Object?> get props => [records, totalCount, leaderboard];

  GroundcheckHistoryLoaded copyWith({
    List<GroundcheckRecord>? records,
    int? totalCount,
    List<Map<String, dynamic>>? leaderboard,
  }) {
    return GroundcheckHistoryLoaded(
      records: records ?? this.records,
      totalCount: totalCount ?? this.totalCount,
      leaderboard: leaderboard ?? this.leaderboard,
    );
  }
}

class GroundcheckHistoryError extends GroundcheckHistoryState {
  final String message;

  const GroundcheckHistoryError({required this.message});

  @override
  List<Object?> get props => [message];
}
