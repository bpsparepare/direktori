import 'package:direktori/features/direktori/domain/entities/direktori.dart';
import 'package:direktori/features/direktori/domain/usecases/get_direktori_stats.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/get_direktori_list.dart';
import 'direktori_event.dart';
import 'direktori_state.dart';

class DirektoriBloc extends Bloc<DirektoriEvent, DirektoriState> {
  final GetDirektoriList getDirektoriList;
  final GetDirektoriCount getDirektoriCount;
  final GetDirektoriStats getDirektoriStats;

  static const int _limit = 20;
  String? _sortColumn = 'nama';
  bool _sortAscending = true;
  bool _includeCoordinates = true;
  List<Direktori> _allCache = const [];
  String? _allCacheSearch;

  List<Direktori> get cachedAllList => _allCache;
  bool get isAllLoaded =>
      state is DirektoriLoaded && (state as DirektoriLoaded).allLoaded;

  DirektoriBloc({
    required this.getDirektoriList,
    required this.getDirektoriCount,
    required this.getDirektoriStats,
  }) : super(DirektoriInitial()) {
    on<LoadDirektoriList>(_onLoadDirektoriList);
    on<SearchDirektori>(_onSearchDirektori);
    on<LoadMoreDirektori>(_onLoadMoreDirektori);
    on<RefreshDirektori>(_onRefreshDirektori);
    on<RefreshDirektoriHeader>(_onRefreshDirektoriHeader);
    on<SortDirektori>(_onSortDirektori);
    on<ToggleIncludeCoordinates>(_onToggleIncludeCoordinates);
    on<LoadAllDirektori>(_onLoadAllDirektori);
  }

  Future<void> _onLoadDirektoriList(
    LoadDirektoriList event,
    Emitter<DirektoriState> emit,
  ) async {
    try {
      if (event.isRefresh || state is DirektoriInitial) {
        emit(DirektoriLoading());
      }

      _sortColumn = event.sortColumn ?? _sortColumn;
      _sortAscending = event.sortAscending;
      _includeCoordinates = event.includeCoordinates;
      final orderBy = _mapSortColumnToOrderBy(_sortColumn);

      final totalCount = await getDirektoriCount(search: event.search);
      final stats = await getDirektoriStats(
        updatedThreshold: DateTime.parse('2025-11-01 13:35:36.438909+00'),
      );
      final direktoriList = await getDirektoriList(
        page: event.page,
        limit: _limit,
        search: event.search,
        orderBy: orderBy,
        ascending: _sortAscending,
        includeCoordinates: _includeCoordinates,
      );

      final hasReachedMax = direktoriList.length < _limit;

      emit(
        DirektoriLoaded(
          direktoriList: direktoriList,
          currentPage: event.page,
          totalCount: totalCount,
          hasReachedMax: hasReachedMax,
          currentSearch: event.search,
          sortColumn: _sortColumn,
          sortAscending: _sortAscending,
          includeCoordinates: _includeCoordinates,
          stats: stats,
          allLoaded: false,
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
    final currentState = state;
    if (currentState is DirektoriLoaded && currentState.allLoaded) {
      final q = event.query.trim();
      final src = _allCache;
      final ql = q.toLowerCase();
      final filtered = q.isEmpty
          ? src
          : src.where((d) {
              final n = d.namaUsaha.toLowerCase();
              final a = (d.alamat ?? '').toLowerCase();
              return n.contains(ql) || a.contains(ql);
            }).toList();
      emit(
        currentState.copyWith(
          direktoriList: filtered,
          currentPage: 1,
          totalCount: filtered.length,
          hasReachedMax: true,
          currentSearch: q.isEmpty ? null : q,
          clearCurrentSearch: q.isEmpty ? true : null,
          isLoadingMore: false,
        ),
      );
    } else {
      final q = event.query.trim();
      add(
        LoadDirektoriList(
          page: 1,
          search: q.isEmpty ? null : q,
          isRefresh: true,
          sortColumn: _sortColumn,
          sortAscending: _sortAscending,
          includeCoordinates: _includeCoordinates,
        ),
      );
    }
  }

  Future<void> _onLoadMoreDirektori(
    LoadMoreDirektori event,
    Emitter<DirektoriState> emit,
  ) async {
    final currentState = state;
    if (currentState is DirektoriLoaded && !currentState.hasReachedMax) {
      if (currentState.allLoaded) {
        // Sudah memuat semua: tidak ada pagination tambahan
        return;
      }
      try {
        emit(currentState.copyWith(isLoadingMore: true));

        final nextPage = currentState.currentPage + 1;
        final moreDirektori = await getDirektoriList(
          page: nextPage,
          limit: _limit,
          search: currentState.currentSearch,
          orderBy: _mapSortColumnToOrderBy(currentState.sortColumn),
          ascending: currentState.sortAscending,
          includeCoordinates: currentState.includeCoordinates,
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
      if (currentState.allLoaded) {
        // Pertahankan list yang sudah dimuat; hanya segarkan header (count/stats)
        try {
          final totalCount = await getDirektoriCount(
            search: currentState.currentSearch,
          );
          final stats = await getDirektoriStats(
            updatedThreshold: DateTime.parse('2025-11-01 13:35:36.438909+00'),
          );
          emit(currentState.copyWith(totalCount: totalCount, stats: stats));
        } catch (_) {}
      } else {
        add(
          LoadDirektoriList(
            page: 1,
            search: currentState.currentSearch,
            isRefresh: true,
            sortColumn: currentState.sortColumn,
            sortAscending: currentState.sortAscending,
            includeCoordinates: currentState.includeCoordinates,
          ),
        );
      }
    } else {
      add(const LoadDirektoriList(page: 1, isRefresh: true));
    }
  }

  Future<void> _onRefreshDirektoriHeader(
    RefreshDirektoriHeader event,
    Emitter<DirektoriState> emit,
  ) async {
    final currentState = state;
    if (currentState is DirektoriLoaded) {
      try {
        final totalCount = await getDirektoriCount(
          search: currentState.currentSearch,
        );
        final stats = await getDirektoriStats(
          updatedThreshold: DateTime.parse('2025-11-01 13:35:36.438909+00'),
        );
        emit(currentState.copyWith(totalCount: totalCount, stats: stats));
      } catch (e) {
        // keep current list; surface error state only if desired
      }
    }
  }

  Future<void> _onSortDirektori(
    SortDirektori event,
    Emitter<DirektoriState> emit,
  ) async {
    _sortColumn = event.column;
    _sortAscending = event.ascending;
    final currentState = state;
    final search = currentState is DirektoriLoaded
        ? currentState.currentSearch
        : null;
    add(
      LoadDirektoriList(
        page: 1,
        search: search,
        isRefresh: true,
        sortColumn: _sortColumn,
        sortAscending: _sortAscending,
        includeCoordinates: _includeCoordinates,
      ),
    );
  }

  String? _mapSortColumnToOrderBy(String? column) {
    switch (column) {
      case 'nama':
        return 'nama_usaha';
      case 'status':
        return 'keberadaan_usaha';
      default:
        return null; // fallback to default order in repository (updated_at desc)
    }
  }

  Future<void> _onToggleIncludeCoordinates(
    ToggleIncludeCoordinates event,
    Emitter<DirektoriState> emit,
  ) async {
    _includeCoordinates = event.include;
    final currentState = state;
    final search = currentState is DirektoriLoaded
        ? currentState.currentSearch
        : null;
    add(
      LoadDirektoriList(
        page: 1,
        search: search,
        isRefresh: true,
        sortColumn: _sortColumn,
        sortAscending: _sortAscending,
        includeCoordinates: _includeCoordinates,
      ),
    );
  }

  Future<void> _onLoadAllDirektori(
    LoadAllDirektori event,
    Emitter<DirektoriState> emit,
  ) async {
    final currentState = state;
    String? search;
    bool include = _includeCoordinates;
    String? sortCol = _sortColumn;
    bool sortAsc = _sortAscending;
    if (currentState is DirektoriLoaded) {
      search = currentState.currentSearch;
      include = currentState.includeCoordinates;
      sortCol = currentState.sortColumn;
      sortAsc = currentState.sortAscending;
      emit(currentState.copyWith(isLoadingMore: true));
    } else {
      emit(DirektoriLoading());
    }

    try {
      final List<Direktori> all = [];
      int page = 1;
      while (true) {
        final batch = await getDirektoriList(
          page: page,
          limit: _limit,
          search: search,
          orderBy: _mapSortColumnToOrderBy(sortCol),
          ascending: sortAsc,
          includeCoordinates: include,
        );
        if (batch.isEmpty) break;
        all.addAll(batch);
        if (batch.length < _limit) break;
        page += 1;
      }

      final totalCount = await getDirektoriCount(search: search);
      final stats = await getDirektoriStats(
        updatedThreshold: DateTime.parse('2025-11-01 13:35:36.438909+00'),
      );

      emit(
        DirektoriLoaded(
          direktoriList: all,
          currentPage: page,
          totalCount: totalCount,
          hasReachedMax: true,
          currentSearch: search,
          sortColumn: sortCol,
          sortAscending: sortAsc,
          includeCoordinates: include,
          stats: stats,
          allLoaded: true,
        ),
      );
      _allCache = all;
      _allCacheSearch = search;
    } catch (e) {
      emit(DirektoriError(e.toString()));
    }
  }
}
