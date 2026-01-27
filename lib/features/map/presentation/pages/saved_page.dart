import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../data/services/groundcheck_supabase_service.dart';
import '../../domain/entities/groundcheck_record.dart';
import 'groundcheck_page.dart';

class DashboardPage extends StatefulWidget {
  final MapController? mapController;

  const DashboardPage({super.key, this.mapController});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final GroundcheckSupabaseService _supabaseService =
      GroundcheckSupabaseService();
  bool _isLoading = true;
  String? _error;

  // Model for dashboard data
  Map<String, int> _totalStats = {};
  Map<String, int> _coordsStats = {};
  int _totalRecords = 0;
  int _totalWithCoords = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final statsData = await _supabaseService.fetchDashboardStats();
      _processData(statsData);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _processData(List<Map<String, dynamic>> statsData) {
    final totalStats = <String, int>{};
    final coordsStats = <String, int>{};
    int total = 0;
    int totalWithCoords = 0;

    for (var row in statsData) {
      final gcs = (row['gcs_result'] ?? '').toString();
      final hasCoords = row['has_coordinates'] == true;
      final count = (row['total_count'] as num).toInt();

      total += count;
      totalStats[gcs] = (totalStats[gcs] ?? 0) + count;

      if (hasCoords) {
        totalWithCoords += count;
        coordsStats[gcs] = (coordsStats[gcs] ?? 0) + count;
      }
    }

    setState(() {
      _totalStats = totalStats;
      _coordsStats = coordsStats;
      _totalRecords = total;
      _totalWithCoords = totalWithCoords;
      _isLoading = false;
    });
  }

  String _getLabelForGcs(String code) {
    switch (code) {
      case '1':
        return 'Ditemukan';
      case '99':
        return 'Tidak Ditemukan';
      case '3':
        return 'Tutup';
      case '4':
        return 'Ganda';
      case '5':
        return 'Usaha Baru';
      case '':
        return 'Belum Dicek';
      default:
        return 'Kode: $code';
    }
  }

  Color _getColorForGcs(String code) {
    switch (code) {
      case '1':
        return Colors.green;
      case '99':
        return Colors.red;
      case '3':
        return Colors.pinkAccent;
      case '4':
        return Colors.purple;
      case '5':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text(
            'Dashboard Statistik',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text('Error: $_error'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadData,
                      child: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadData,
                child: ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    _buildSummaryCard(),
                    const SizedBox(height: 24),
                    const Text(
                      'Detail Hasil GCS',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildStatsList(),
                    const SizedBox(height: 100), // Bottom padding
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Text(
              'Total Data',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              '$_totalRecords',
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMiniStat(
                  'Sudah Dicek',
                  _totalRecords - (_totalStats[''] ?? 0),
                  Colors.green,
                ),
                _buildMiniStat(
                  'Belum Dicek',
                  _totalStats[''] ?? 0,
                  Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMiniStat('Ada Koordinat', _totalWithCoords, Colors.blue),
                _buildMiniStat(
                  'Tanpa Koordinat',
                  _totalRecords - _totalWithCoords,
                  Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      ],
    );
  }

  Widget _buildStatsList() {
    // Sort keys: custom order or alphabetically
    final sortedKeys = _totalStats.keys.toList()
      ..sort((a, b) {
        if (a == '') return 1; // Put empty (Belum Dicek) last
        if (b == '') return -1;
        return a.compareTo(b);
      });

    return Column(
      children: sortedKeys.map((key) {
        final count = _totalStats[key] ?? 0;
        final countWithCoords = _coordsStats[key] ?? 0;
        final percentage = _totalRecords > 0 ? (count / _totalRecords) : 0.0;
        final label = _getLabelForGcs(key);
        final color = _getColorForGcs(key);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$count (${(percentage * 100).toStringAsFixed(1)}%)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Ada Coord: $countWithCoords',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percentage,
                  backgroundColor: color.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 8,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
