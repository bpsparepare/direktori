import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/contribution_bloc.dart';
import '../bloc/contribution_event.dart';
import '../bloc/contribution_state.dart';
import '../widgets/contribution_stats_widget.dart';
import '../widgets/contribution_list_widget.dart';
import '../widgets/leaderboard_widget.dart';
import 'contribution_history_page.dart';
import 'leaderboard_page.dart';

/// Halaman utama untuk fitur kontribusi
class ContributionPage extends StatefulWidget {
  const ContributionPage({super.key});

  @override
  State<ContributionPage> createState() => _ContributionPageState();
}

class _ContributionPageState extends State<ContributionPage> {
  @override
  void initState() {
    super.initState();
    // Load initial data for summary: stats and recent contributions
    context.read<ContributionBloc>().add(const GetUserStatsEvent());
    // Ambil hanya 5 kontribusi terbaru untuk ringkasan
    // Ambil lebih banyak baris lalu batasi 5 setelah pengelompokan di UI
    context.read<ContributionBloc>().add(
      const GetUserContributionsEvent(limit: 25),
    );
    context.read<ContributionBloc>().add(const GetUserRankEvent());
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<ContributionBloc, ContributionState>(
        listener: (context, state) {
          if (state is ContributionError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          } else if (state is ContributionCreated) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Kontribusi berhasil dibuat!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        builder: (context, state) {
          // Tampilkan ringkasan pribadi (stats + sebagian history)
          return _buildDashboardTab(state);
        },
      ),
    );
  }

  Widget _buildDashboardTab(ContributionState state) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<ContributionBloc>().add(
          const RefreshAllContributionDataEvent(),
        );
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats Widget (dengan tombol Leaderboard di header)
            ContributionStatsWidget(
              onViewLeaderboard: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LeaderboardPage()),
                );
                // Pastikan daftar ringkas kembali ke 5 teratas setelah kembali
                // Ambil lebih banyak baris lalu batasi 5 setelah pengelompokan di UI
                context.read<ContributionBloc>().add(
                  const GetUserContributionsEvent(limit: 50),
                );
              },
            ),

            const SizedBox(height: 24),

            // Recent Contributions
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Kontribusi Terbaru',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        TextButton(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ContributionHistoryPage(),
                              ),
                            );
                            // Refresh kembali daftar ringkas 5 item
                            // Ambil lebih banyak baris lalu batasi 5 setelah pengelompokan di UI
                            context.read<ContributionBloc>().add(
                              const GetUserContributionsEvent(limit: 50),
                            );
                          },
                          child: const Text('Lihat Semua'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const ContributionListWidget(isCompact: true, limit: 5),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTab(ContributionState state) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<ContributionBloc>().add(const GetUserContributionsEvent());
      },
      child: const Padding(
        padding: EdgeInsets.all(16.0),
        child: ContributionListWidget(),
      ),
    );
  }

  Widget _buildLeaderboardTab(ContributionState state) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<ContributionBloc>().add(const GetLeaderboardEvent());
      },
      child: const Padding(
        padding: EdgeInsets.all(16.0),
        child: LeaderboardWidget(),
      ),
    );
  }

  // Form kontribusi dinonaktifkan sesuai keputusan; helper dihapus.
}
