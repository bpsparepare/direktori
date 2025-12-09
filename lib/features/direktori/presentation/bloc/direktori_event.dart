import 'package:equatable/equatable.dart';

abstract class DirektoriEvent extends Equatable {
  const DirektoriEvent();

  @override
  List<Object?> get props => [];
}

class LoadDirektoriList extends DirektoriEvent {
  final int page;
  final String? search;
  final bool isRefresh;
  final String? sortColumn; // 'nama' | 'status'
  final bool sortAscending;
  final bool includeCoordinates;

  const LoadDirektoriList({
    required this.page,
    this.search,
    this.isRefresh = false,
    this.sortColumn,
    this.sortAscending = false,
    this.includeCoordinates = false,
  });

  @override
  List<Object?> get props => [
    page,
    search,
    isRefresh,
    sortColumn,
    sortAscending,
    includeCoordinates,
  ];
}

class SearchDirektori extends DirektoriEvent {
  final String query;

  const SearchDirektori(this.query);

  @override
  List<Object?> get props => [query];
}

class LoadMoreDirektori extends DirektoriEvent {
  const LoadMoreDirektori();
}

class RefreshDirektori extends DirektoriEvent {
  const RefreshDirektori();
}

class RefreshDirektoriHeader extends DirektoriEvent {
  const RefreshDirektoriHeader();
}

class LoadAllDirektori extends DirektoriEvent {
  const LoadAllDirektori();
}

class SortDirektori extends DirektoriEvent {
  final String column; // 'nama' | 'status'
  final bool ascending;

  const SortDirektori({required this.column, required this.ascending});

  @override
  List<Object?> get props => [column, ascending];
}

class ToggleIncludeCoordinates extends DirektoriEvent {
  final bool include;

  const ToggleIncludeCoordinates(this.include);

  @override
  List<Object?> get props => [include];
}
