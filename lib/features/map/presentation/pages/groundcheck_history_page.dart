import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/services/groundcheck_supabase_service.dart';
import '../bloc/groundcheck_history_bloc.dart';
import '../bloc/groundcheck_history_event.dart';
import '../bloc/groundcheck_history_state.dart';
import 'groundcheck_page.dart';

class GroundcheckHistoryPage extends StatelessWidget {
  const GroundcheckHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          GroundcheckHistoryBloc(service: GroundcheckSupabaseService())
            ..add(const LoadGroundcheckHistory()),
      child: const _GroundcheckHistoryView(),
    );
  }
}

class _GroundcheckHistoryView extends StatefulWidget {
  const _GroundcheckHistoryView();

  @override
  State<_GroundcheckHistoryView> createState() =>
      _GroundcheckHistoryViewState();
}

class _GroundcheckHistoryViewState extends State<_GroundcheckHistoryView> {
  String _userName = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final service = GroundcheckSupabaseService();
    final name = await service.fetchCurrentUserName();
    if (mounted) {
      setState(() {
        _userName = name ?? 'Unknown User';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get current user ID for highlighting self in leaderboard
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'Unknown';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kontribusi & Peringkat'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.history), text: 'Riwayat Saya'),
              Tab(icon: Icon(Icons.leaderboard), text: 'Peringkat Global'),
            ],
          ),
        ),
        body: BlocBuilder<GroundcheckHistoryBloc, GroundcheckHistoryState>(
          builder: (context, state) {
            if (state is GroundcheckHistoryLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is GroundcheckHistoryError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      state.message,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        context.read<GroundcheckHistoryBloc>().add(
                          const LoadGroundcheckHistory(),
                        );
                      },
                      child: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              );
            } else if (state is GroundcheckHistoryLoaded) {
              return TabBarView(
                children: [
                  // Tab 1: History
                  RefreshIndicator(
                    onRefresh: () async {
                      context.read<GroundcheckHistoryBloc>().add(
                        const LoadGroundcheckHistory(),
                      );
                    },
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Card(
                            elevation: 4,
                            color: Colors.blue[50],
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: Colors.blue,
                                    child: const Icon(
                                      Icons.person,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Halo, $_userName',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'Total Kontribusi Saya',
                                          style: TextStyle(fontSize: 14),
                                        ),
                                        Text(
                                          '${state.records.length}',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: state.records.isEmpty
                              ? const Center(
                                  child: Text('Belum ada riwayat kontribusi'),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  itemCount: state.records.length,
                                  itemBuilder: (context, index) {
                                    final record = state.records[index];
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.all(
                                          12,
                                        ),
                                        leading: CircleAvatar(
                                          backgroundColor: _getStatusColor(
                                            record.gcsResult,
                                          ),
                                          child: Text(
                                            record.gcsResult.isNotEmpty
                                                ? record.gcsResult
                                                : '?',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          record.namaUsaha.isNotEmpty
                                              ? record.namaUsaha
                                              : 'Tanpa Nama',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 4),
                                            Text(
                                              record.alamatUsaha,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[200],
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'ID: ${record.idsbr}',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  fontFamily: 'Monospace',
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),

                  // Tab 2: Leaderboard
                  RefreshIndicator(
                    onRefresh: () async {
                      context.read<GroundcheckHistoryBloc>().add(
                        LoadGroundcheckLeaderboard(),
                      );
                    },
                    child: state.leaderboard.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.leaderboard_outlined,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Belum ada data peringkat',
                                  style: TextStyle(color: Colors.grey),
                                ),
                                Text(
                                  'Pastikan View sudah dibuat di database',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: state.leaderboard.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, index) {
                              final item = state.leaderboard[index];
                              final isMe = item['user_id'] == userId;
                              final rank = index + 1;
                              final userName =
                                  item['user_name'] ??
                                  item['user_id'] ??
                                  'Unknown';

                              return ListTile(
                                tileColor: isMe
                                    ? Colors.blue.withOpacity(0.1)
                                    : null,
                                leading: CircleAvatar(
                                  backgroundColor: rank <= 3
                                      ? Colors.amber
                                      : Colors.grey[300],
                                  foregroundColor: rank <= 3
                                      ? Colors.black
                                      : Colors.grey[700],
                                  child: Text('#$rank'),
                                ),
                                title: Text(
                                  userName.toString(),
                                  style: TextStyle(
                                    fontWeight: isMe
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${item['total_contribution']}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                    const Text(
                                      'Kontribusi',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case '1':
        return Colors.green;
      case '0':
        return Colors.red;
      case '3':
        return Colors.orange;
      case '4':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
