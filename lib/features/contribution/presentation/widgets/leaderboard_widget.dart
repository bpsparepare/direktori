import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/leaderboard_entry.dart';
import '../bloc/contribution_bloc.dart';
import '../bloc/contribution_event.dart';
import '../bloc/contribution_state.dart';

/// Widget untuk menampilkan leaderboard kontributor
class LeaderboardWidget extends StatefulWidget {
  final String period;
  final int limit;

  const LeaderboardWidget({
    super.key,
    this.period = 'monthly',
    this.limit = 50,
  });

  @override
  State<LeaderboardWidget> createState() => _LeaderboardWidgetState();
}

class _LeaderboardWidgetState extends State<LeaderboardWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedPeriod = 'monthly';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _selectedPeriod = widget.period;
    _loadLeaderboard();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadLeaderboard() {
    context.read<ContributionBloc>().add(
      GetLeaderboardEvent(period: _selectedPeriod, limit: widget.limit),
    );
  }

  void _onPeriodChanged(String period) {
    setState(() {
      _selectedPeriod = period;
    });
    _loadLeaderboard();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildPeriodSelector(),
        const SizedBox(height: 16),
        Expanded(
          child: BlocBuilder<ContributionBloc, ContributionState>(
            builder: (context, state) {
              if (state is ContributionLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (state is ContributionError) {
                return _buildErrorState(state.message);
              }

              List<LeaderboardEntry> entries = [];

              if (state is LeaderboardLoaded) {
                entries = state.leaderboard;
              } else if (state is ContributionLoaded &&
                  state.leaderboard != null) {
                entries = state.leaderboard!;
              }

              if (entries.isEmpty) {
                return _buildEmptyState();
              }

              return _buildLeaderboard(entries);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPeriodTab('Mingguan', 'weekly'),
          _buildPeriodTab('Bulanan', 'monthly'),
          _buildPeriodTab('Sepanjang Masa', 'all_time'),
        ],
      ),
    );
  }

  Widget _buildPeriodTab(String label, String period) {
    final isSelected = _selectedPeriod == period;

    return GestureDetector(
      onTap: () => _onPeriodChanged(period),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).primaryColor
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboard(List<LeaderboardEntry> entries) {
    return RefreshIndicator(
      onRefresh: () async {
        _loadLeaderboard();
      },
      child: ListView.builder(
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _buildLeaderboardItem(entry, index + 1);
        },
      ),
    );
  }

  Widget _buildLeaderboardItem(LeaderboardEntry entry, int rank) {
    final isTopThree = rank <= 3;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: isTopThree ? 4 : 1,
      child: Container(
        decoration: isTopThree
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  colors: _getRankGradient(rank),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              )
            : null,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: _buildRankBadge(rank),
          title: Text(
            entry.userName,
            style: TextStyle(
              fontWeight: isTopThree ? FontWeight.bold : FontWeight.w500,
              color: isTopThree ? Colors.white : null,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Level ${entry.level}',
                style: TextStyle(
                  color: isTopThree ? Colors.white70 : Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.star,
                    size: 16,
                    color: isTopThree ? Colors.white70 : Colors.amber,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${entry.totalContributions} kontribusi',
                    style: TextStyle(
                      color: isTopThree ? Colors.white70 : Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.totalPoints}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isTopThree
                      ? Colors.white
                      : Theme.of(context).primaryColor,
                ),
              ),
              Text(
                'poin',
                style: TextStyle(
                  fontSize: 12,
                  color: isTopThree ? Colors.white70 : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRankBadge(int rank) {
    Widget child;

    if (rank <= 3) {
      child = Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(child: _getRankIcon(rank)),
      );
    } else {
      child = CircleAvatar(
        backgroundColor: Colors.grey[200],
        child: Text(
          '$rank',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
      );
    }

    return child;
  }

  Widget _getRankIcon(int rank) {
    switch (rank) {
      case 1:
        return const Icon(Icons.emoji_events, color: Colors.amber, size: 24);
      case 2:
        return const Icon(Icons.emoji_events, color: Colors.grey, size: 22);
      case 3:
        return const Icon(Icons.emoji_events, color: Colors.brown, size: 20);
      default:
        return Text('$rank');
    }
  }

  List<Color> _getRankGradient(int rank) {
    switch (rank) {
      case 1:
        return [Colors.amber[400]!, Colors.amber[600]!];
      case 2:
        return [Colors.grey[400]!, Colors.grey[600]!];
      case 3:
        return [Colors.brown[400]!, Colors.brown[600]!];
      default:
        return [Colors.blue[400]!, Colors.blue[600]!];
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.leaderboard_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Belum ada data leaderboard',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Mulai berkontribusi untuk muncul di leaderboard',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Gagal memuat leaderboard',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadLeaderboard,
            child: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }
}
