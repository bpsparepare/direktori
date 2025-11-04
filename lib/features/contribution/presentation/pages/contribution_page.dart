import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/contribution_bloc.dart';
import '../bloc/contribution_event.dart';
import '../bloc/contribution_state.dart';
import '../widgets/contribution_stats_widget.dart';
import '../widgets/contribution_list_widget.dart';
import '../widgets/leaderboard_widget.dart';
import '../widgets/contribution_form_widget.dart';

/// Halaman utama untuk fitur kontribusi
class ContributionPage extends StatefulWidget {
  const ContributionPage({super.key});

  @override
  State<ContributionPage> createState() => _ContributionPageState();
}

class _ContributionPageState extends State<ContributionPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Load initial data
    context.read<ContributionBloc>().add(const GetUserContributionsEvent());
  }

  @override
  void dispose() {
    _tabController.dispose();
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
          // Tampilkan hanya Riwayat kontribusi
          return _buildHistoryTab(state);
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
            // Stats Widget
            const ContributionStatsWidget(),

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
                          onPressed: () => _tabController.animateTo(1),
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

            // (Aksi Cepat dihapus sesuai permintaan)
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

  void _showContributionForm(BuildContext context, {String? actionType}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ContributionFormWidget(),
      ),
    );
  }
}
