import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/user_contribution.dart';
import '../bloc/contribution_bloc.dart';
import '../bloc/contribution_event.dart';
import '../bloc/contribution_state.dart';

/// Widget untuk menampilkan daftar kontribusi pengguna
class ContributionListWidget extends StatefulWidget {
  final bool isCompact;
  final int? limit;
  final String? status;

  const ContributionListWidget({
    super.key,
    this.isCompact = false,
    this.limit,
    this.status,
  });

  @override
  State<ContributionListWidget> createState() => _ContributionListWidgetState();
}

class _ContributionListWidgetState extends State<ContributionListWidget> {
  final ScrollController _scrollController = ScrollController();
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy, HH:mm');

  @override
  void initState() {
    super.initState();
    _loadContributions();

    if (!widget.isCompact) {
      _scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadContributions() {
    context.read<ContributionBloc>().add(
      GetUserContributionsEvent(limit: widget.limit, status: widget.status),
    );
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      // Load more contributions when reaching the bottom
      // This would require implementing pagination in the BLoC
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ContributionBloc, ContributionState>(
      builder: (context, state) {
        if (state is ContributionLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is ContributionError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Gagal memuat kontribusi',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  state.message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadContributions,
                  child: const Text('Coba Lagi'),
                ),
              ],
            ),
          );
        }

        List<UserContribution> contributions = [];

        if (state is ContributionLoaded) {
          contributions = state.contributions;
        } else if (state is ContributionEmpty) {
          return _buildEmptyState();
        }

        if (contributions.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          controller: widget.isCompact ? null : _scrollController,
          shrinkWrap: widget.isCompact,
          physics: widget.isCompact
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          itemCount: contributions.length,
          itemBuilder: (context, index) {
            final contribution = contributions[index];
            return _buildContributionCard(context, contribution);
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Belum ada kontribusi',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Mulai berkontribusi untuk melihat riwayat di sini',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildContributionCard(
    BuildContext context,
    UserContribution contribution,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _buildActionIcon(contribution.actionType),
        title: Text(
          _getActionTitle(contribution.actionType, contribution.targetType),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Target: ${contribution.targetId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _buildStatusChip(contribution.status),
                const SizedBox(width: 8),
                Text(
                  _dateFormat.format(contribution.createdAt),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '+${contribution.points}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.green[700],
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'poin',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
        onTap: () => _showContributionDetails(context, contribution),
      ),
    );
  }

  Widget _buildActionIcon(String actionType) {
    IconData icon;
    Color color;

    switch (actionType) {
      case 'create':
        icon = Icons.add_location;
        color = Colors.green;
        break;
      case 'update':
        icon = Icons.edit_location;
        color = Colors.blue;
        break;
      case 'delete':
        icon = Icons.delete_outline;
        color = Colors.red;
        break;
      case 'verify':
        icon = Icons.verified;
        color = Colors.purple;
        break;
      default:
        icon = Icons.help_outline;
        color = Colors.grey;
    }

    return CircleAvatar(
      backgroundColor: color.withOpacity(0.1),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    String label;

    switch (status) {
      case 'pending':
        color = Colors.orange;
        label = 'Menunggu';
        break;
      case 'approved':
        color = Colors.green;
        label = 'Disetujui';
        break;
      case 'rejected':
        color = Colors.red;
        label = 'Ditolak';
        break;
      default:
        color = Colors.grey;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _getActionTitle(String actionType, String targetType) {
    final target = _getTargetName(targetType);

    switch (actionType) {
      case 'create':
        return 'Menambah $target';
      case 'update':
        return 'Memperbarui $target';
      case 'delete':
        return 'Menghapus $target';
      case 'verify':
        return 'Memverifikasi $target';
      default:
        return 'Aksi pada $target';
    }
  }

  String _getTargetName(String targetType) {
    switch (targetType) {
      case 'direktori':
        return 'Direktori';
      case 'location':
        return 'Lokasi';
      case 'business':
        return 'Bisnis';
      default:
        return targetType;
    }
  }

  void _showContributionDetails(
    BuildContext context,
    UserContribution contribution,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _getActionTitle(contribution.actionType, contribution.targetType),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('ID', contribution.id),
            _buildDetailRow('Target', contribution.targetId),
            _buildDetailRow('Status', contribution.status),
            _buildDetailRow('Poin', '+${contribution.points}'),
            _buildDetailRow(
              'Dibuat',
              _dateFormat.format(contribution.createdAt),
            ),
            if (contribution.changes != null &&
                contribution.changes!.isNotEmpty)
              _buildDetailRow('Perubahan', contribution.changes.toString()),
            if (contribution.latitude != null && contribution.longitude != null)
              _buildDetailRow(
                'Koordinat',
                '${contribution.latitude!.toStringAsFixed(6)}, ${contribution.longitude!.toStringAsFixed(6)}',
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
