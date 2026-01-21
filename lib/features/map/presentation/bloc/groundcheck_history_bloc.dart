import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/services/groundcheck_supabase_service.dart';
import 'groundcheck_history_event.dart';
import 'groundcheck_history_state.dart';

class GroundcheckHistoryBloc
    extends Bloc<GroundcheckHistoryEvent, GroundcheckHistoryState> {
  final GroundcheckSupabaseService _service;

  GroundcheckHistoryBloc({required GroundcheckSupabaseService service})
    : _service = service,
      super(GroundcheckHistoryInitial()) {
    on<LoadGroundcheckHistory>(_onLoadGroundcheckHistory);
    on<LoadGroundcheckLeaderboard>(_onLoadGroundcheckLeaderboard);
  }

  Future<void> _onLoadGroundcheckLeaderboard(
    LoadGroundcheckLeaderboard event,
    Emitter<GroundcheckHistoryState> emit,
  ) async {
    try {
      final leaderboard = await _service.fetchLeaderboard();

      if (state is GroundcheckHistoryLoaded) {
        emit(
          (state as GroundcheckHistoryLoaded).copyWith(
            leaderboard: leaderboard,
          ),
        );
      } else {
        emit(
          GroundcheckHistoryLoaded(
            records: const [],
            totalCount: 0,
            leaderboard: leaderboard,
          ),
        );
      }
    } catch (e) {
      emit(
        GroundcheckHistoryError(
          message: 'Failed to load leaderboard: ${e.toString()}',
        ),
      );
    }
  }

  Future<void> _onLoadGroundcheckHistory(
    LoadGroundcheckHistory event,
    Emitter<GroundcheckHistoryState> emit,
  ) async {
    emit(GroundcheckHistoryLoading());
    try {
      String? userId = event.userId;
      if (userId == null) {
        // Try to get current user ID from Supabase Auth
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          // If the table uses auth_uid or we need to map it, we might need fetchCurrentUserId
          // But GroundcheckRecord uses user_id which seems to be the ID from users table or auth ID?
          // Based on the schema provided: "user_id"
          // Let's assume it matches what fetchCurrentUserId returns or just auth.uid if they are the same.
          // GroundcheckSupabaseService has fetchCurrentUserId which queries 'users' table.
          // Let's use that to be safe.
          userId = await _service.fetchCurrentUserId();
          if (userId == null) {
            // Fallback to auth id if fetchCurrentUserId fails/returns null but we have a user
            userId = user.id;
          }
        }
      }

      if (userId == null) {
        emit(const GroundcheckHistoryError(message: 'User not logged in'));
        return;
      }

      final records = await _service.fetchUserRecords(userId);
      // Load leaderboard as well initially
      final leaderboard = await _service.fetchLeaderboard();
      emit(
        GroundcheckHistoryLoaded(
          records: records,
          totalCount: records.length,
          leaderboard: leaderboard,
        ),
      );
    } catch (e) {
      emit(
        GroundcheckHistoryError(
          message: 'Failed to load history: ${e.toString()}',
        ),
      );
    }
  }
}
