import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/direktori_bloc.dart';
import '../bloc/direktori_event.dart';
import '../bloc/direktori_state.dart';
import '../widgets/direktori_table.dart';
import '../widgets/direktori_search_bar.dart';
import '../../domain/usecases/get_direktori_list.dart';
import '../../data/repositories/direktori_repository_impl.dart';
import '../../data/datasources/direktori_remote_datasource.dart';
import '../../../map/data/repositories/map_repository_impl.dart';

class DirektoriListPage extends StatelessWidget {
  const DirektoriListPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final mapRepository = MapRepositoryImpl();
        final remoteDataSource = DirektoriRemoteDataSourceImpl(
          mapRepository: mapRepository,
        );
        final repository = DirektoriRepositoryImpl(
          remoteDataSource: remoteDataSource,
        );
        final getDirektoriList = GetDirektoriList(repository);
        final getDirektoriCount = GetDirektoriCount(repository);

        return DirektoriBloc(
          getDirektoriList: getDirektoriList,
          getDirektoriCount: getDirektoriCount,
        );
      },
      child: const _DirektoriListView(),
    );
  }
}

class _DirektoriListView extends StatefulWidget {
  const _DirektoriListView({Key? key}) : super(key: key);

  @override
  State<_DirektoriListView> createState() => _DirektoriListViewState();
}

class _DirektoriListViewState extends State<_DirektoriListView> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Load initial data
    context.read<DirektoriBloc>().add(const LoadDirektoriList(page: 1));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isBottom) {
      context.read<DirektoriBloc>().add(const LoadMoreDirektori());
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  void _onSearch(String query) {
    context.read<DirektoriBloc>().add(SearchDirektori(query));
  }

  void _onRefresh() {
    context.read<DirektoriBloc>().add(const RefreshDirektori());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.business, size: 24, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Text(
                        'Direktori Usaha',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _onRefresh,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DirektoriSearchBar(
                    controller: _searchController,
                    onSearch: _onSearch,
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: BlocBuilder<DirektoriBloc, DirektoriState>(
                builder: (context, state) {
                  if (state is DirektoriLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state is DirektoriError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Terjadi kesalahan',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.message,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _onRefresh,
                            child: const Text('Coba Lagi'),
                          ),
                        ],
                      ),
                    );
                  }

                  if (state is DirektoriLoaded) {
                    if (state.direktoriList.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.business_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              state.currentSearch?.isNotEmpty == true
                                  ? 'Tidak ada hasil untuk "${state.currentSearch}"'
                                  : 'Belum ada data direktori',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            if (state.currentSearch?.isNotEmpty == true) ...[
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearch('');
                                },
                                child: const Text('Hapus pencarian'),
                              ),
                            ],
                          ],
                        ),
                      );
                    }

                    return Column(
                      children: [
                        // Results info
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Text(
                                'Menampilkan ${state.direktoriList.length} dari ${state.totalCount} data',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                              if (state.currentSearch?.isNotEmpty == true) ...[
                                const SizedBox(width: 8),
                                Chip(
                                  label: Text(
                                    'Pencarian: ${state.currentSearch}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onDeleted: () {
                                    _searchController.clear();
                                    _onSearch('');
                                  },
                                  deleteIcon: const Icon(Icons.close, size: 16),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Table
                        Expanded(
                          child: DirektoriTable(
                            direktoriList: state.direktoriList,
                            scrollController: _scrollController,
                            isLoadingMore: state.isLoadingMore,
                            hasReachedMax: state.hasReachedMax,
                          ),
                        ),
                      ],
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
