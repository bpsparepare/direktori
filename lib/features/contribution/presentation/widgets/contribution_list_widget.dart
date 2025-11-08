import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/user_contribution.dart';
import '../bloc/contribution_bloc.dart';
import '../bloc/contribution_event.dart';
import '../bloc/contribution_state.dart';
import '../../../map/presentation/pages/main_page.dart';

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

  String _formatRelativeTime(DateTime createdAt, [String? timestampStr]) {
    DateTime base = createdAt;
    if (timestampStr != null && timestampStr.isNotEmpty) {
      try {
        base = DateTime.parse(timestampStr);
      } catch (_) {
        // ignore parse error, fallback to createdAt
      }
    }

    final now = DateTime.now();
    final diff = now.difference(base);

    if (diff.inSeconds < 60) {
      return 'baru saja';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} menit lalu';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} jam lalu';
    }
    if (diff.inDays < 30) {
      return '${diff.inDays} hari lalu';
    }
    final months = diff.inDays ~/ 30;
    if (months < 12) {
      return '$months bulan lalu';
    }
    final years = diff.inDays ~/ 365;
    return '$years tahun lalu';
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
      buildWhen: (previous, current) =>
          current is ContributionLoading ||
          current is ContributionLoaded ||
          current is ContributionEmpty ||
          current is ContributionError,
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

        if (state is ContributionEmpty) {
          return _buildEmptyState();
        }

        if (state is! ContributionLoaded) {
          // Pada state awal atau state non-kontribusi, tampilkan loader agar tidak terlihat kosong
          return const Center(child: CircularProgressIndicator());
        }

        final List<UserContribution> contributions = state.contributions;
        final List<UserContribution> displayContributions =
            (widget.limit != null && contributions.isNotEmpty)
            ? contributions.take(widget.limit!).toList()
            : contributions;

        if (displayContributions.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          controller: widget.isCompact ? null : _scrollController,
          shrinkWrap: widget.isCompact,
          physics: widget.isCompact
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          itemCount: displayContributions.length,
          itemBuilder: (context, index) {
            final contribution = displayContributions[index];
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
    final changes = contribution.changes ?? {};
    final namaUsaha = (changes['nama_usaha']?.toString() ?? '').trim();
    final alamat = (changes['alamat']?.toString() ?? '').trim();
    final waktuLabel = _formatRelativeTime(
      contribution.createdAt,
      changes['timestamp']?.toString(),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openMapForContribution(context, contribution),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildActionIcon(contribution.actionType),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      namaUsaha.isNotEmpty
                          ? namaUsaha
                          : _getActionTitle(
                              contribution.actionType,
                              contribution.targetType,
                            ),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (alamat.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          alamat,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: Colors.grey[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            waktuLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '+${contribution.points}',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'poin',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  _buildStatusChip(contribution.status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMapForContribution(BuildContext context, UserContribution c) {
    final dirId = _extractDirectoryId(c);
    if (dirId == null || dirId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada direktori.id terkait kontribusi ini'),
        ),
      );
      return;
    }

    // Navigasi ke halaman utama peta dan fokus pada direktori tersebut
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MainPage(initialTabIndex: 0),
        settings: RouteSettings(arguments: {'focusDirectoryId': dirId}),
      ),
    );
  }

  String? _extractDirectoryId(UserContribution c) {
    // Prioritas: targetId (langsung), fallback ke changes['target_uuid']
    final targetId = c.targetId;
    if (targetId.isNotEmpty) return targetId;
    final changes = c.changes;
    final fromChanges = changes != null
        ? changes['target_uuid']?.toString()
        : null;
    return fromChanges;
  }

  /// Menampilkan ringkasan isi `changes` (contoh: nama_usaha, alamat, koordinat, timestamp, target_uuid)
  Widget _buildChangesPreview(
    BuildContext context,
    Map<String, dynamic> changes,
  ) {
    final namaUsaha = changes['nama_usaha']?.toString();
    final alamat = changes['alamat']?.toString();
    final lat = changes['latitude'];
    final lng = changes['longitude'];
    final timestampStr = changes['timestamp']?.toString();
    final targetUuid = changes['target_uuid']?.toString();

    String? coords;
    if (lat is num && lng is num) {
      coords =
          '${lat.toDouble().toStringAsFixed(6)}, ${lng.toDouble().toStringAsFixed(6)}';
    }

    String? waktu;
    if (timestampStr != null && timestampStr.isNotEmpty) {
      try {
        final dt = DateTime.parse(timestampStr);
        waktu = _formatRelativeTime(dt);
      } catch (_) {
        waktu = timestampStr; // fallback tampilkan apa adanya
      }
    }

    final textStyle = Theme.of(context).textTheme.bodySmall;
    final greyStyle = textStyle?.copyWith(color: Colors.grey[700]);

    final rows = <Widget>[];
    if (namaUsaha != null && namaUsaha.isNotEmpty) {
      rows.add(Text('Nama: $namaUsaha', style: textStyle));
    }
    if (alamat != null && alamat.isNotEmpty) {
      rows.add(Text('Alamat: $alamat', style: textStyle));
    }
    if (coords != null) {
      rows.add(Text('Koordinat: $coords', style: greyStyle));
    }
    if (waktu != null) {
      rows.add(Text('Waktu: $waktu', style: greyStyle));
    }
    if (targetUuid != null && targetUuid.isNotEmpty) {
      rows.add(Text('UUID Target: $targetUuid', style: greyStyle));
    }

    // Jika tidak ada key yang dikenal, tampilkan ringkas seluruh changes
    if (rows.isEmpty) {
      rows.add(
        Text(
          'Perubahan: ${changes.toString()}',
          style: textStyle,
          overflow: TextOverflow.ellipsis,
          maxLines: 3,
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
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
