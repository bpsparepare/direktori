import 'package:equatable/equatable.dart';
import '../../domain/entities/direktori.dart';

abstract class DirektoriState extends Equatable {
  const DirektoriState();

  @override
  List<Object?> get props => [];
}

class DirektoriInitial extends DirektoriState {}

class DirektoriLoading extends DirektoriState {}

class DirektoriLoaded extends DirektoriState {
  final List<Direktori> direktoriList;
  final int currentPage;
  final int totalCount;
  final bool hasReachedMax;
  final String? currentSearch;
  final bool isLoadingMore;
  final String? sortColumn; // 'nama' | 'status'
  final bool sortAscending;
  final bool includeCoordinates;
  final Map<String, int>? stats;
  final bool allLoaded;

  const DirektoriLoaded({
    required this.direktoriList,
    required this.currentPage,
    required this.totalCount,
    required this.hasReachedMax,
    this.currentSearch,
    this.isLoadingMore = false,
    this.sortColumn,
    this.sortAscending = false,
    this.includeCoordinates = false,
    this.stats,
    this.allLoaded = false,
  });

  DirektoriLoaded copyWith({
    List<Direktori>? direktoriList,
    int? currentPage,
    int? totalCount,
    bool? hasReachedMax,
    String? currentSearch,
    bool? isLoadingMore,
    String? sortColumn,
    bool? sortAscending,
    bool? includeCoordinates,
    Map<String, int>? stats,
    bool? allLoaded,
  }) {
    return DirektoriLoaded(
      direktoriList: direktoriList ?? this.direktoriList,
      currentPage: currentPage ?? this.currentPage,
      totalCount: totalCount ?? this.totalCount,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      currentSearch: currentSearch ?? this.currentSearch,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      sortColumn: sortColumn ?? this.sortColumn,
      sortAscending: sortAscending ?? this.sortAscending,
      includeCoordinates: includeCoordinates ?? this.includeCoordinates,
      stats: stats ?? this.stats,
      allLoaded: allLoaded ?? this.allLoaded,
    );
  }

  @override
  List<Object?> get props => [
    direktoriList,
    currentPage,
    totalCount,
    hasReachedMax,
    currentSearch,
    isLoadingMore,
    sortColumn,
    sortAscending,
    includeCoordinates,
    stats,
    allLoaded,
  ];
}

class DirektoriError extends DirektoriState {
  final String message;

  const DirektoriError(this.message);

  @override
  List<Object?> get props => [message];
}
