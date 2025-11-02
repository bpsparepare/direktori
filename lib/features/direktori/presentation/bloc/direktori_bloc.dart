import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/get_direktori_list.dart';
import 'direktori_event.dart';
import 'direktori_state.dart';

class DirektoriBloc extends Bloc<DirektoriEvent, DirektoriState> {
  final GetDirektoriList getDirektoriList;
  final GetDirektoriCount getDirektoriCount;

  static const int _limit = 20;

  DirektoriBloc({
    required this.getDirektoriList,
    required this.getDirektoriCount,
  }) : super(DirektoriInitial()) {
    on<LoadDirektoriList>(_onLoadDirektoriList);
    on<SearchDirektori>(_onSearchDirektori);
    on<LoadMoreDirektori>(_onLoadMoreDirektori);
    on<RefreshDirektori>(_onRefreshDirektori);
  }

  Future<void> _onLoadDirektoriList(
    LoadDirektoriList event,
    Emitter<DirektoriState> emit,
  ) async {
    try {
      if (event.isRefresh || state is DirektoriInitial) {
        emit(DirektoriLoading());
      }

      final totalCount = await getDirektoriCount(search: event.search);
      final direktoriList = await getDirektoriList(
        page: event.page,
        limit: _limit,
        search: event.search,
      );

      final hasReachedMax = direktoriList.length < _limit;

      emit(
        DirektoriLoaded(
          direktoriList: direktoriList,
          currentPage: event.page,
          totalCount: totalCount,
          hasReachedMax: hasReachedMax,
          currentSearch: event.search,
        ),
      );
    } catch (e) {
      emit(DirektoriError(e.toString()));
    }
  }

  Future<void> _onSearchDirektori(
    SearchDirektori event,
    Emitter<DirektoriState> emit,
  ) async {
    add(LoadDirektoriList(page: 1, search: event.query, isRefresh: true));
  }

  Future<void> _onLoadMoreDirektori(
    LoadMoreDirektori event,
    Emitter<DirektoriState> emit,
  ) async {
    final currentState = state;
    if (currentState is DirektoriLoaded && !currentState.hasReachedMax) {
      try {
        emit(currentState.copyWith(isLoadingMore: true));

        final nextPage = currentState.currentPage + 1;
        final moreDirektori = await getDirektoriList(
          page: nextPage,
          limit: _limit,
          search: currentState.currentSearch,
        );

        final hasReachedMax = moreDirektori.length < _limit;
        final updatedList = List.of(currentState.direktoriList)
          ..addAll(moreDirektori);

        emit(
          currentState.copyWith(
            direktoriList: updatedList,
            currentPage: nextPage,
            hasReachedMax: hasReachedMax,
            isLoadingMore: false,
          ),
        );
      } catch (e) {
        emit(currentState.copyWith(isLoadingMore: false));
        emit(DirektoriError(e.toString()));
      }
    }
  }

  Future<void> _onRefreshDirektori(
    RefreshDirektori event,
    Emitter<DirektoriState> emit,
  ) async {
    final currentState = state;
    if (currentState is DirektoriLoaded) {
      add(
        LoadDirektoriList(
          page: 1,
          search: currentState.currentSearch,
          isRefresh: true,
        ),
      );
    } else {
      add(const LoadDirektoriList(page: 1, isRefresh: true));
    }
  }
}
