import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../../data/services/groundcheck_supabase_service.dart';

class SpasialPage extends StatefulWidget {
  const SpasialPage({super.key});

  @override
  State<SpasialPage> createState() => _SpasialPageState();
}

class _SpasialPageState extends State<SpasialPage> {
  final GroundcheckSupabaseService _supabaseService =
      GroundcheckSupabaseService();

  bool _isLoading = true;
  String? _error;
  List<SpasialSummary> _summaryData = [];

  @override
  void initState() {
    super.initState();
    _loadAndCalculate();
  }

  Future<void> _loadAndCalculate() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // 1. Load Metadata
      final metadataString = await rootBundle.loadString(
        'assets/json/sls_metadata.json',
      );
      final List<dynamic> metadataJson = jsonDecode(metadataString);
      // Map<KecCode+DesaCode, Metadata>
      final Map<String, _Metadata> metadataMap = {};

      for (var item in metadataJson) {
        final idsls = item['idsls'] as String;
        // 73 72 011 001 (10 chars)
        if (idsls.length >= 10) {
          final key = idsls.substring(0, 10);
          if (!metadataMap.containsKey(key)) {
            metadataMap[key] = _Metadata(
              nmKec: item['nmkec'] ?? '',
              nmDesa: item['nmdesa'] ?? '',
            );
          }
        }
      }

      // 2. Load GeoJSON
      final geoJsonString = await rootBundle.loadString(
        'assets/geojson/final_sls_optimized.json',
      );
      final geoJson = jsonDecode(geoJsonString);
      final features = geoJson['features'] as List;

      final List<_SlsPolygon> polygons = [];

      for (var feature in features) {
        final props = feature['properties'];
        final idsls = props['idsls'] as String;
        final geometry = feature['geometry'];
        final type = geometry['type'];
        final coordinates = geometry['coordinates'] as List;

        if (type == 'MultiPolygon') {
          for (var poly in coordinates) {
            // poly is List<List<Position>> (Ring)
            // usually index 0 is outer ring
            final outerRing = poly[0] as List;
            final points = outerRing.map((p) {
              return LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble());
            }).toList();
            polygons.add(_SlsPolygon(idsls: idsls, points: points));
          }
        } else if (type == 'Polygon') {
          final outerRing = coordinates[0] as List;
          final points = outerRing.map((p) {
            return LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble());
          }).toList();
          polygons.add(_SlsPolygon(idsls: idsls, points: points));
        }
      }

      // 3. Load Records
      final records = await _supabaseService.loadLocalRecords();

      // 4. Calculate
      final Map<String, int> counts = {}; // Key: 10 digit code
      final Map<String, int> countsBelumGc = {};
      final Map<String, int> countsDitemukan = {};
      final Map<String, int> countsTidakDitemukan = {};
      final Map<String, int> countsTutup = {};
      final Map<String, int> countsGanda = {};
      final Map<String, int> countsUsahaBaru = {};

      int outsideCount = 0;
      int outsideBelumGc = 0;
      int outsideDitemukan = 0;
      int outsideTidakDitemukan = 0;
      int outsideTutup = 0;
      int outsideGanda = 0;
      int outsideUsahaBaru = 0;

      for (var record in records) {
        final lat = double.tryParse(record.latitude);
        final lng = double.tryParse(record.longitude);

        if (lat != null && lng != null && lat != 0 && lng != 0) {
          final point = LatLng(lat, lng);
          bool found = false;

          // Determine status code
          // Mapping logic from groundcheck_page.dart
          // '' -> Belum GC
          // '99' or contains 'tidak ditemukan' -> Tidak Ditemukan
          // '1' or contains 'ditemukan' -> Ditemukan
          // '3' or contains 'tutup' -> Tutup
          // '4' or contains 'ganda' -> Ganda
          // '5' or contains 'usaha baru' -> Usaha Baru

          final lower = record.gcsResult.toLowerCase();
          int statusCode =
              0; // 0: Belum GC, 1: Ditemukan, 3: Tutup, 4: Ganda, 5: Usaha Baru, 99: Tidak Ditemukan

          if (lower == '' || lower == 'null') {
            statusCode = 0;
          } else if (lower == '99' || lower.contains('tidak ditemukan')) {
            statusCode = 99;
          } else if (lower == '1' || lower.contains('ditemukan')) {
            statusCode = 1;
          } else if (lower == '3' || lower.contains('tutup')) {
            statusCode = 3;
          } else if (lower == '4' || lower.contains('ganda')) {
            statusCode = 4;
          } else if (lower == '5' || lower.contains('usaha baru')) {
            statusCode = 5;
          } else {
            // Default/Fallback
            if (record.isUploaded) {
              // Assume uploaded means done, but what kind?
              // If not matched above, maybe treat as 'Ditemukan' or just keep as is?
              // Let's assume 0 (Belum GC) if really unknown, or map strictly.
              // For now, let's stick to the explicit rules.
              // If gcsResult is something else, maybe it counts towards total but not specific breakdown?
              // Let's map to Belum GC (0) if unknown.
              statusCode = 0;
            }
          }

          // Find which polygon
          for (var poly in polygons) {
            if (_isPointInPolygon(point, poly.points)) {
              if (poly.idsls.length >= 10) {
                final key = poly.idsls.substring(0, 10);
                counts[key] = (counts[key] ?? 0) + 1;

                if (statusCode == 0) {
                  countsBelumGc[key] = (countsBelumGc[key] ?? 0) + 1;
                } else if (statusCode == 1) {
                  countsDitemukan[key] = (countsDitemukan[key] ?? 0) + 1;
                } else if (statusCode == 99) {
                  countsTidakDitemukan[key] =
                      (countsTidakDitemukan[key] ?? 0) + 1;
                } else if (statusCode == 3) {
                  countsTutup[key] = (countsTutup[key] ?? 0) + 1;
                } else if (statusCode == 4) {
                  countsGanda[key] = (countsGanda[key] ?? 0) + 1;
                } else if (statusCode == 5) {
                  countsUsahaBaru[key] = (countsUsahaBaru[key] ?? 0) + 1;
                }

                found = true;
                break;
              }
            }
          }

          if (!found) {
            outsideCount++;
            if (statusCode == 0) {
              outsideBelumGc++;
            } else if (statusCode == 1) {
              outsideDitemukan++;
            } else if (statusCode == 99) {
              outsideTidakDitemukan++;
            } else if (statusCode == 3) {
              outsideTutup++;
            } else if (statusCode == 4) {
              outsideGanda++;
            } else if (statusCode == 5) {
              outsideUsahaBaru++;
            }
          }
        }
      }

      // 5. Aggregate Results
      final List<SpasialSummary> results = [];

      metadataMap.forEach((key, meta) {
        results.add(
          SpasialSummary(
            kecamatan: meta.nmKec,
            desa: meta.nmDesa,
            count: counts[key] ?? 0,
            countBelumGc: countsBelumGc[key] ?? 0,
            countDitemukan: countsDitemukan[key] ?? 0,
            countTidakDitemukan: countsTidakDitemukan[key] ?? 0,
            countTutup: countsTutup[key] ?? 0,
            countGanda: countsGanda[key] ?? 0,
            countUsahaBaru: countsUsahaBaru[key] ?? 0,
          ),
        );
      });

      // Sort by Kecamatan then Desa
      results.sort((a, b) {
        int cmp = a.kecamatan.compareTo(b.kecamatan);
        if (cmp != 0) return cmp;
        return a.desa.compareTo(b.desa);
      });

      // Add "Lainnya" (Outside polygons) if > 0
      if (outsideCount > 0) {
        results.add(
          SpasialSummary(
            kecamatan: 'LAINNYA',
            desa: 'LUAR WILAYAH',
            count: outsideCount,
            countBelumGc: outsideBelumGc,
            countDitemukan: outsideDitemukan,
            countTidakDitemukan: outsideTidakDitemukan,
            countTutup: outsideTutup,
            countGanda: outsideGanda,
            countUsahaBaru: outsideUsahaBaru,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _summaryData = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // Ray Casting Algorithm
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    bool c = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      if (((polygon[i].latitude > point.latitude) !=
              (polygon[j].latitude > point.latitude)) &&
          (point.longitude <
              (polygon[j].longitude - polygon[i].longitude) *
                      (point.latitude - polygon[i].latitude) /
                      (polygon[j].latitude - polygon[i].latitude) +
                  polygon[i].longitude)) {
        c = !c;
      }
    }
    return c;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Progres Wilayah (Spasial)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadAndCalculate,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Total Wilayah: ${_summaryData.length}\n'
                  'Total Titik Terpetakan: ${_summaryData.fold(0, (sum, item) => sum + item.count)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Kecamatan')),
                  DataColumn(label: Text('Desa/Kelurahan')),
                  DataColumn(label: Text('Total Titik'), numeric: true),
                  DataColumn(label: Text('Belum GC'), numeric: true),
                  DataColumn(label: Text('Ditemukan'), numeric: true),
                  DataColumn(label: Text('Tidak Ditemukan'), numeric: true),
                  DataColumn(label: Text('Tutup'), numeric: true),
                  DataColumn(label: Text('Ganda'), numeric: true),
                  DataColumn(label: Text('Usaha Baru'), numeric: true),
                ],
                rows: [
                  ..._summaryData.map((item) {
                    return DataRow(
                      cells: [
                        DataCell(Text(item.kecamatan)),
                        DataCell(Text(item.desa)),
                        DataCell(Text(item.count.toString())),
                        DataCell(Text(item.countBelumGc.toString())),
                        DataCell(Text(item.countDitemukan.toString())),
                        DataCell(Text(item.countTidakDitemukan.toString())),
                        DataCell(Text(item.countTutup.toString())),
                        DataCell(Text(item.countGanda.toString())),
                        DataCell(Text(item.countUsahaBaru.toString())),
                      ],
                    );
                  }),
                  DataRow(
                    color: WidgetStateProperty.all(Colors.grey.shade200),
                    cells: [
                      const DataCell(
                        Text(
                          'TOTAL',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const DataCell(Text('')),
                      DataCell(
                        Text(
                          _summaryData
                              .fold(0, (s, i) => s + i.count)
                              .toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataCell(
                        Text(
                          _summaryData
                              .fold(0, (s, i) => s + i.countBelumGc)
                              .toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataCell(
                        Text(
                          _summaryData
                              .fold(0, (s, i) => s + i.countDitemukan)
                              .toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataCell(
                        Text(
                          _summaryData
                              .fold(0, (s, i) => s + i.countTidakDitemukan)
                              .toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataCell(
                        Text(
                          _summaryData
                              .fold(0, (s, i) => s + i.countTutup)
                              .toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataCell(
                        Text(
                          _summaryData
                              .fold(0, (s, i) => s + i.countGanda)
                              .toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataCell(
                        Text(
                          _summaryData
                              .fold(0, (s, i) => s + i.countUsahaBaru)
                              .toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SpasialSummary {
  final String kecamatan;
  final String desa;
  final int count;
  final int countBelumGc;
  final int countDitemukan;
  final int countTidakDitemukan;
  final int countTutup;
  final int countGanda;
  final int countUsahaBaru;

  SpasialSummary({
    required this.kecamatan,
    required this.desa,
    required this.count,
    required this.countBelumGc,
    required this.countDitemukan,
    required this.countTidakDitemukan,
    required this.countTutup,
    required this.countGanda,
    required this.countUsahaBaru,
  });
}

class _Metadata {
  final String nmKec;
  final String nmDesa;

  _Metadata({required this.nmKec, required this.nmDesa});
}

class _SlsPolygon {
  final String idsls;
  final List<LatLng> points;

  _SlsPolygon({required this.idsls, required this.points});
}
