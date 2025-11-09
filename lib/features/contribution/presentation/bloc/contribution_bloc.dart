import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import '../../domain/repositories/contribution_repository.dart';
import '../../domain/usecases/create_contribution_usecase.dart';
import '../../domain/usecases/get_user_stats_usecase.dart';
import '../../domain/usecases/get_user_contributions_usecase.dart';
import '../../domain/usecases/get_leaderboard_usecase.dart';
import 'contribution_event.dart';
import 'contribution_state.dart';

/// BLoC untuk mengelola state kontribusi pengguna
class ContributionBloc extends Bloc<ContributionEvent, ContributionState> {
  final ContributionRepository _repository;
  final CreateContributionUseCase _createContributionUseCase;
  final GetUserStatsUseCase _getUserStatsUseCase;
  final GetUserContributionsUseCase _getUserContributionsUseCase;
  final GetLeaderboardUseCase _getLeaderboardUseCase;

  ContributionBloc({
    required ContributionRepository repository,
    required CreateContributionUseCase createContributionUseCase,
    required GetUserStatsUseCase getUserStatsUseCase,
    required GetUserContributionsUseCase getUserContributionsUseCase,
    required GetLeaderboardUseCase getLeaderboardUseCase,
  }) : _repository = repository,
       _createContributionUseCase = createContributionUseCase,
       _getUserStatsUseCase = getUserStatsUseCase,
       _getUserContributionsUseCase = getUserContributionsUseCase,
       _getLeaderboardUseCase = getLeaderboardUseCase,
       super(const ContributionInitial()) {
    // Register event handlers
    on<CreateContributionEvent>(_onCreateContribution);
    on<LinkContributionsToDirectoryEvent>(_onLinkContributionsToDirectory);
    on<GetUserContributionsEvent>(_onGetUserContributions);
    on<UpdateContributionStatusEvent>(_onUpdateContributionStatus);
    on<GetUserStatsEvent>(_onGetUserStats);
    on<RefreshUserStatsEvent>(_onRefreshUserStats);
    on<GetLeaderboardEvent>(_onGetLeaderboard);
    on<GetUserRankEvent>(_onGetUserRank);
    on<GetContributionStatsEvent>(_onGetContributionStats);
    on<GetRecentContributionsEvent>(_onGetRecentContributions);
    on<ResetContributionStateEvent>(_onResetState);
    on<RefreshAllContributionDataEvent>(_onRefreshAllData);
  }

  /// Handler untuk membuat kontribusi baru
  Future<void> _onCreateContribution(
    CreateContributionEvent event,
    Emitter<ContributionState> emit,
  ) async {
    try {
      print('🎯 [BLOC] CreateContributionEvent diterima');
      print('🎯 [BLOC] Action Type: ${event.actionType}');
      print('📍 [BLOC] Target Type: ${event.targetType}');
      print('🆔 [BLOC] Target ID: ${event.targetId}');

      // Update state untuk menunjukkan sedang membuat kontribusi
      if (state is ContributionLoaded) {
        emit(
          (state as ContributionLoaded).copyWith(isCreatingContribution: true),
        );
      } else {
        emit(
          const ContributionOperationInProgress(
            operation: 'creating_contribution',
            message: 'Membuat kontribusi...',
          ),
        );
      }

      // Get current user ID
      final userId = _repository.getCurrentUserId();
      if (userId == null) {
        print('❌ [BLOC] User tidak terautentikasi');
        emit(const ContributionError(message: 'User tidak terautentikasi'));
        return;
      }

      print('👤 [BLOC] User ID: $userId');

      // Create contribution
      print('🔄 [BLOC] Memanggil use case untuk membuat kontribusi...');
      final contribution = await _createContributionUseCase(
        userId: userId,
        actionType: event.actionType,
        targetType: event.targetType,
        targetId: event.targetId,
        changes: event.changes,
        latitude: event.latitude,
        longitude: event.longitude,
        operationId: event.operationId,
      );

      print('✅ [BLOC] Kontribusi berhasil dibuat: ${contribution.id}');
      emit(ContributionCreated(contribution: contribution));

      // Refresh data after creating contribution
      print('🔄 [BLOC] Memperbarui data kontribusi...');
      add(const RefreshAllContributionDataEvent());
    } catch (e, st) {
      _logError('CreateContribution', e, st);
      emit(
        ContributionError(message: 'Gagal membuat kontribusi: ${e.toString()}'),
      );
    }
  }

  /// Handler untuk mengambil kontribusi pengguna
  Future<void> _onGetUserContributions(
    GetUserContributionsEvent event,
    Emitter<ContributionState> emit,
  ) async {
    try {
      // Get user ID from event or current user
      final userId = event.userId ?? _repository.getCurrentUserId();

      print('📋 [BLOC] GetUserContributionsEvent diterima');
      print('👤 [BLOC] User ID: ${userId ?? "null"}');
      print('📊 [BLOC] Limit: ${event.limit}, Offset: ${event.offset}');

      if (userId == null) {
        print('❌ [BLOC] User tidak terautentikasi');
        emit(const ContributionError(message: 'User tidak terautentikasi'));
        return;
      }

      emit(const ContributionLoading());

      print('🔄 [BLOC] Memanggil use case untuk mengambil kontribusi...');
      final contributions = await _getUserContributionsUseCase(
        userId: userId,
        limit: event.limit,
        offset: event.offset,
        status: event.status,
      );

      print('✅ [BLOC] Berhasil mengambil ${contributions.length} kontribusi');

      emit(ContributionLoaded(contributions: contributions));
    } catch (e, st) {
      _logError('GetUserContributions', e, st);
      emit(
        ContributionError(message: 'Gagal memuat kontribusi: ${e.toString()}'),
      );
    }
  }

  /// Handler untuk update status kontribusi
  Future<void> _onUpdateContributionStatus(
    UpdateContributionStatusEvent event,
    Emitter<ContributionState> emit,
  ) async {
    try {
      if (state is ContributionLoaded) {
        emit((state as ContributionLoaded).copyWith(isUpdatingStatus: true));
      } else {
        emit(
          const ContributionOperationInProgress(
            operation: 'updating_status',
            message: 'Memperbarui status...',
          ),
        );
      }

      final success = await _repository.updateContributionStatus(
        contributionId: event.contributionId,
        status: event.status,
      );

      if (success) {
        emit(
          ContributionStatusUpdated(
            contributionId: event.contributionId,
            newStatus: event.status,
          ),
        );

        // Refresh contributions after update
        add(const GetUserContributionsEvent());
      } else {
        emit(
          const ContributionError(
            message: 'Gagal memperbarui status kontribusi',
          ),
        );
      }
    } catch (e, st) {
      _logError('UpdateContributionStatus', e, st);
      emit(
        ContributionError(message: 'Gagal memperbarui status: ${e.toString()}'),
      );
    }
  }

  /// Handler untuk mendapatkan statistik pengguna
  Future<void> _onGetUserStats(
    GetUserStatsEvent event,
    Emitter<ContributionState> emit,
  ) async {
    try {
      final userId = event.userId ?? _repository.getCurrentUserId();
      if (userId == null) {
        emit(const ContributionError(message: 'User tidak terautentikasi'));
        return;
      }

      final userStats = await _getUserStatsUseCase(userId);

      if (userStats != null) {
        emit(UserStatsLoaded(userStats: userStats));
      } else {
        emit(
          const ContributionError(
            message: 'Statistik pengguna tidak ditemukan',
          ),
        );
      }
    } catch (e, st) {
      _logError('GetUserStats', e, st);
      emit(
        ContributionError(message: 'Gagal memuat statistik: ${e.toString()}'),
      );
    }
  }

  /// Handler untuk refresh statistik pengguna
  Future<void> _onRefreshUserStats(
    RefreshUserStatsEvent event,
    Emitter<ContributionState> emit,
  ) async {
    try {
      final userId = event.userId ?? _repository.getCurrentUserId();
      if (userId == null) return;

      // Update stats in database (usually handled by triggers)
      await _repository.updateUserStats(userId);

      // Get updated stats
      add(GetUserStatsEvent(userId: userId));
    } catch (e, st) {
      _logError('RefreshUserStats', e, st);
      emit(
        ContributionError(message: 'Gagal refresh statistik: ${e.toString()}'),
      );
    }
  }

  /// Handler untuk mendapatkan leaderboard
  Future<void> _onGetLeaderboard(
    GetLeaderboardEvent event,
    Emitter<ContributionState> emit,
  ) async {
    try {
      final leaderboard = await _getLeaderboardUseCase(
        limit: event.limit,
        offset: event.offset,
        period: event.period,
      );

      emit(LeaderboardLoaded(leaderboard: leaderboard, period: event.period));
    } catch (e, st) {
      _logError('GetLeaderboard', e, st);
      emit(
        ContributionError(message: 'Gagal memuat leaderboard: ${e.toString()}'),
      );
    }
  }

  /// Handler untuk mendapatkan ranking pengguna
  Future<void> _onGetUserRank(
    GetUserRankEvent event,
    Emitter<ContributionState> emit,
  ) async {
    try {
      final userId = event.userId ?? _repository.getCurrentUserId();
      if (userId == null) {
        emit(const ContributionError(message: 'User tidak terautentikasi'));
        return;
      }

      final rank = await _repository.getUserRank(userId);
      emit(UserRankLoaded(rank: rank));
    } catch (e, st) {
      _logError('GetUserRank', e, st);
      emit(ContributionError(message: 'Gagal memuat ranking: ${e.toString()}'));
    }
  }

  /// Handler untuk mendapatkan statistik kontribusi
  Future<void> _onGetContributionStats(
    GetContributionStatsEvent event,
    Emitter<ContributionState> emit,
  ) async {
    try {
      final userId = event.userId ?? _repository.getCurrentUserId();

      final stats = await _repository.getContributionStats(
        userId: userId,
        startDate: event.startDate,
        endDate: event.endDate,
      );

      emit(ContributionStatsLoaded(stats: stats));
    } catch (e, st) {
      _logError('GetContributionStats', e, st);
      emit(
        ContributionError(message: 'Gagal memuat statistik: ${e.toString()}'),
      );
    }
  }

  /// Handler untuk mendapatkan kontribusi terbaru
  Future<void> _onGetRecentContributions(
    GetRecentContributionsEvent event,
    Emitter<ContributionState> emit,
  ) async {
    try {
      final contributions = await _repository.getRecentContributions(
        limit: event.limit,
        actionType: event.actionType,
      );

      emit(ContributionLoaded(contributions: contributions));
    } catch (e, st) {
      _logError('GetRecentContributions', e, st);
      emit(
        ContributionError(
          message: 'Gagal memuat kontribusi terbaru: ${e.toString()}',
        ),
      );
    }
  }

  /// Handler untuk reset state
  Future<void> _onResetState(
    ResetContributionStateEvent event,
    Emitter<ContributionState> emit,
  ) async {
    emit(const ContributionInitial());
  }

  /// Handler untuk refresh semua data
  Future<void> _onRefreshAllData(
    RefreshAllContributionDataEvent event,
    Emitter<ContributionState> emit,
  ) async {
    try {
      final userId = _repository.getCurrentUserId();
      if (userId == null) return;

      // Get all data concurrently
      final futures = await Future.wait([
        _getUserContributionsUseCase(userId: userId),
        _getUserStatsUseCase(userId),
        _getLeaderboardUseCase(),
        _repository.getContributionStats(userId: userId),
        _repository.getUserRank(userId),
      ]);

      final contributions = futures[0] as List<dynamic>;
      final userStats = futures[1] as dynamic;
      final leaderboard = futures[2] as List<dynamic>;
      final stats = futures[3] as Map<String, int>;
      final rank = futures[4] as int;

      emit(
        ContributionLoaded(
          contributions: contributions.cast(),
          userStats: userStats,
          leaderboard: leaderboard.cast(),
          contributionStats: stats,
          userRank: rank,
        ),
      );
    } catch (e, st) {
      debugPrint('ContributionBloc: _onRefreshAllData error: $e');
      debugPrintStack(label: 'ContributionBloc stack', stackTrace: st);
      emit(ContributionError(message: 'Gagal refresh data1: ${e.toString()}'));
    }
  }

  // Helper untuk logging error terstruktur
  void _logError(String scope, Object error, StackTrace stack) {
    debugPrint('❌ [BLOC] $scope error: $error');
    debugPrintStack(label: 'ContributionBloc $scope stack', stackTrace: stack);
  }

  /// Handler untuk menautkan kontribusi ke direktori berdasarkan UUID
  Future<void> _onLinkContributionsToDirectory(
    LinkContributionsToDirectoryEvent event,
    Emitter<ContributionState> emit,
  ) async {
    try {
      debugPrint(
        '🔗 [BLOC] LinkContributionsToDirectoryEvent: ${event.directoryId}',
      );
      final count = await _repository.linkContributionsToDirectory(
        event.directoryId,
      );
      debugPrint(
        '🔗 [BLOC] Linked $count contributions to directory ${event.directoryId}',
      );
      // No state change required; this is a background reconciliation step.
    } catch (e, st) {
      _logError('LinkContributionsToDirectory', e, st);
      // Keep UX stable; do not emit error state for background linking.
    }
  }
}
