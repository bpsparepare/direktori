import 'package:flutter/material.dart';
import '../../domain/entities/direktori.dart';

class DirektoriTable extends StatelessWidget {
  final List<Direktori> direktoriList;
  final ScrollController scrollController;
  final bool isLoadingMore;
  final bool hasReachedMax;

  const DirektoriTable({
    Key? key,
    required this.direktoriList,
    required this.scrollController,
    required this.isLoadingMore,
    required this.hasReachedMax,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: scrollController,
      child: Column(
        children: [
          // Table
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(3), // Nama Usaha
                  1: FlexColumnWidth(2), // Alamat
                  2: FlexColumnWidth(2), // Kegiatan Usaha
                  3: FlexColumnWidth(1), // Aksi
                },
                children: [
                  // Header
                  TableRow(
                    decoration: BoxDecoration(color: Colors.blue[50]),
                    children: const [
                      _TableHeader('Nama Usaha'),
                      _TableHeader('Alamat'),
                      _TableHeader('Kegiatan Usaha'),
                      _TableHeader('Aksi'),
                    ],
                  ),
                  // Data rows
                  ...direktoriList.map((direktori) => _buildDataRow(direktori)),
                ],
              ),
            ),
          ),
          // Loading more indicator
          if (isLoadingMore)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          // End of data indicator
          if (hasReachedMax && direktoriList.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Semua data telah dimuat',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
          // Bottom spacing for scroll
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  TableRow _buildDataRow(Direktori direktori) {
    return TableRow(
      children: [
        _TableCell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                direktori.namaUsaha,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (direktori.namaKomersialUsaha?.isNotEmpty == true) ...[
                const SizedBox(height: 2),
                Text(
                  direktori.namaKomersialUsaha!,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        _TableCell(
          child: Text(
            direktori.alamat ?? '-',
            style: const TextStyle(fontSize: 13),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _TableCell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (direktori.kegiatanUsaha.isNotEmpty)
                ...direktori.kegiatanUsaha
                    .take(2)
                    .map(
                      (kegiatan) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          kegiatan['nama'] ?? kegiatan.toString(),
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
              else
                const Text('-', style: TextStyle(fontSize: 12)),
              if (direktori.kegiatanUsaha.length > 2)
                Text(
                  '+${direktori.kegiatanUsaha.length - 2} lainnya',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blue[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
        _TableCell(
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (value) {
              switch (value) {
                case 'detail':
                  _showDetailDialog(direktori);
                  break;
                case 'edit':
                  // TODO: Implement edit functionality
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'detail',
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16),
                    SizedBox(width: 8),
                    Text('Detail'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 16),
                    SizedBox(width: 8),
                    Text('Edit'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showDetailDialog(Direktori direktori) {
    // TODO: Implement detail dialog
  }
}

class _TableHeader extends StatelessWidget {
  final String title;

  const _TableHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: Colors.black87,
        ),
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  final Widget child;

  const _TableCell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: child,
    );
  }
}
