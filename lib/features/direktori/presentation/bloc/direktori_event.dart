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

  const LoadDirektoriList({
    required this.page,
    this.search,
    this.isRefresh = false,
  });

  @override
  List<Object?> get props => [page, search, isRefresh];
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
