import 'package:csv/csv.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../data/services/groundcheck_supabase_service.dart';
import '../../domain/entities/groundcheck_record.dart';

class DuplicateRecord {
  final String groupId;
  final String confidence;
  final String confidenceScore;
  final String recommendation;
  final String perusahaanId;
  final String namaUsaha;
  final String alamat;
  final String reasoning;

  DuplicateRecord({
    required this.groupId,
    required this.confidence,
    required this.confidenceScore,
    required this.recommendation,
    required this.perusahaanId,
    required this.namaUsaha,
    required this.alamat,
    required this.reasoning,
  });

  factory DuplicateRecord.fromList(List<dynamic> row) {
    return DuplicateRecord(
      groupId: row[0].toString().trim(),
      confidence: row[1].toString().trim(),
      confidenceScore: row[2].toString().trim(),
      recommendation: row[3].toString().trim(),
      perusahaanId: row[4].toString().trim(),
      namaUsaha: row[5].toString().trim(),
      alamat: row[6].toString().trim(),
      reasoning: row[7].toString().trim(),
    );
  }
}

class DuplicateGroup {
  final String groupId;
  final List<DuplicateRecord> records;

  DuplicateGroup({required this.groupId, required this.records});
}

class _GeocodeResult {
  final LatLng location;
  final LatLng? viewportNE;
  final LatLng? viewportSW;

  _GeocodeResult(this.location, {this.viewportNE, this.viewportSW});
}

class DuplicatePage extends StatefulWidget {
  final void Function(GroundcheckRecord record)? onGoToMap;

  const DuplicatePage({super.key, this.onGoToMap});

  @override
  State<DuplicatePage> createState() => _DuplicatePageState();
}

class _DuplicatePageState extends State<DuplicatePage> {
  List<DuplicateGroup> _groups = [];
  Map<String, GroundcheckRecord> _localDataMap = {};
  bool _isLoading = true;
  String? _error;
  final Set<String> _selectedIds = {}; // Track selected IDs for bulk edit

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // Load local groundcheck data
      final service = GroundcheckSupabaseService();
      final localRecords = await service.loadLocalRecords();
      final Map<String, GroundcheckRecord> localMap = {};

      for (var record in localRecords) {
        // Map by perusahaanId (preferred) and idsbr (fallback)
        // Trim IDs to ensure matching works
        if (record.perusahaanId.isNotEmpty) {
          localMap[record.perusahaanId.trim()] = record;
        }
        if (record.idsbr.isNotEmpty) {
          localMap[record.idsbr.trim()] = record;
        }
      }

      final csvString = await rootBundle.loadString(
        'assets/geojson/ai_agent_duplicate_groups_records.csv',
      );

      // Parse CSV
      // Remove eol parameter to let the converter handle different EOL styles automatically
      List<List<dynamic>> rows = const CsvToListConverter().convert(
        csvString,
        fieldDelimiter: ',',
        textDelimiter: '"',
      );

      if (rows.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Remove header
      // Header: group_id,confidence,confidence_score,recommendation,perusahaan_id,nama_usaha,alamat,your_reasoning
      // final header = rows.first; // Unused
      // Simple validation or just skip
      final dataRows = rows.skip(1).toList();

      final Map<String, List<DuplicateRecord>> groupedData = {};

      for (var row in dataRows) {
        if (row.length < 8) continue; // Skip invalid rows
        final record = DuplicateRecord.fromList(row);
        if (!groupedData.containsKey(record.groupId)) {
          groupedData[record.groupId] = [];
        }
        groupedData[record.groupId]!.add(record);
      }

      final List<DuplicateGroup> groups = groupedData.entries.map((entry) {
        return DuplicateGroup(groupId: entry.key, records: entry.value);
      }).toList();

      // Sort by Group ID (numeric aware)
      groups.sort((a, b) {
        // Extract numbers from "DUP_123" format
        final regExp = RegExp(r'(\d+)');
        final matchA = regExp.firstMatch(a.groupId);
        final matchB = regExp.firstMatch(b.groupId);

        if (matchA != null && matchB != null) {
          final numA = int.parse(matchA.group(1)!);
          final numB = int.parse(matchB.group(1)!);
          final result = numA.compareTo(numB);
          if (result != 0) return result;
        }

        // Fallback to string comparison
        return a.groupId.compareTo(b.groupId);
      });

      if (mounted) {
        setState(() {
          _groups = groups;
          _localDataMap = localMap;
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

  Future<void> _handleBulkGroupResolve() async {
    if (_selectedIds.length != 1) return;

    final selectedId = _selectedIds.first;
    DuplicateGroup? targetGroup;

    // Find the group containing the selected ID
    for (var group in _groups) {
      bool foundInGroup = false;
      for (var record in group.records) {
        // Resolve the ID for this record exactly as in DataTable
        final localRecord =
            _localDataMap[record.perusahaanId.trim()] ??
            _localDataMap[record.perusahaanId.replaceAll(
              RegExp(r'[^0-9]'),
              '',
            )];

        final recSelectionId = localRecord?.perusahaanId.isNotEmpty == true
            ? localRecord!.perusahaanId
            : (localRecord?.idsbr.isNotEmpty == true
                  ? localRecord!.idsbr
                  : record.perusahaanId);

        if (recSelectionId == selectedId) {
          foundInGroup = true;
          break;
        }
      }
      if (foundInGroup) {
        targetGroup = group;
        break;
      }
    }

    if (targetGroup == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grup tidak ditemukan for ID terpilih.')),
      );
      return;
    }

    // Confirmation Dialog
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Penyelesaian Grup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Akan menerapkan status berikut:'),
            const SizedBox(height: 8),
            const Text('• ID Terpilih ➔ 1. Ditemukan'),
            Text(
              '• ${targetGroup!.records.length - 1} ID Lainnya di Grup ➔ 4. Ganda',
            ),
            const SizedBox(height: 16),
            const Text('Lanjutkan?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ya'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;

    try {
      final service = GroundcheckSupabaseService();
      // Load fresh data
      final localRecords = await service.loadLocalRecords();
      final updatedRecords = <GroundcheckRecord>[];
      final Map<String, GroundcheckRecord> updatedMap = Map.from(_localDataMap);

      // Create a set of all IDs involved in this group (resolved IDs)
      // and a mapping to know which one is the "selected" one
      final groupRecordIds = <String>{};

      for (var record in targetGroup.records) {
        final localRecord =
            _localDataMap[record.perusahaanId.trim()] ??
            _localDataMap[record.perusahaanId.replaceAll(
              RegExp(r'[^0-9]'),
              '',
            )];

        final recSelectionId = localRecord?.perusahaanId.isNotEmpty == true
            ? localRecord!.perusahaanId
            : (localRecord?.idsbr.isNotEmpty == true
                  ? localRecord!.idsbr
                  : record.perusahaanId);

        groupRecordIds.add(recSelectionId);
      }

      // Update records in memory
      final recordsToSync = <GroundcheckRecord>[];
      for (var record in localRecords) {
        // Determine if this record is part of the group
        // We need to check if its ID matches any of the resolved IDs in the group
        // But localRecords items ARE the source of truth for IDs.

        String? matchingGroupId;
        if (groupRecordIds.contains(record.perusahaanId)) {
          matchingGroupId = record.perusahaanId;
        } else if (groupRecordIds.contains(record.idsbr)) {
          matchingGroupId = record.idsbr;
        }

        if (matchingGroupId != null) {
          String newStatus;
          if (matchingGroupId == selectedId) {
            newStatus = '1'; // Ditemukan
          } else {
            newStatus = '4'; // Ganda
          }

          // Logic: Skip if uploaded and status is same
          if (record.isUploaded && record.gcsResult == newStatus) {
            updatedRecords.add(record);
            continue;
          }

          // Logic isUploaded: If uploaded, set false and mark as revisi
          final bool wasUploaded = record.isUploaded;
          final updated = record.copyWith(
            gcsResult: newStatus,
            isUploaded: wasUploaded ? false : record.isUploaded,
            isRevisi: wasUploaded ? true : record.isRevisi,
          );

          updatedRecords.add(updated);
          recordsToSync.add(updated);

          // Update local map directly
          if (updated.perusahaanId.isNotEmpty) {
            updatedMap[updated.perusahaanId.trim()] = updated;
          }
          if (updated.idsbr.isNotEmpty) {
            updatedMap[updated.idsbr.trim()] = updated;
          }
        } else {
          updatedRecords.add(record);
        }
      }

      // Sync to Supabase
      if (recordsToSync.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Menyimpan ke database...'),
            duration: Duration(seconds: 1),
          ),
        );
        await service.upsertRecords(recordsToSync);
      }

      // Save back to local storage
      await service.saveLocalRecords(updatedRecords);

      if (mounted) {
        setState(() {
          _localDataMap = updatedMap;
          _selectedIds.clear(); // Clear selection
        });

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status grup berhasil diperbarui')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal memperbarui status: $e')));
      }
    }
  }

  Future<void> _handleBulkEditStatus() async {
    if (_selectedIds.isEmpty) return;

    // Use the same dialog logic as GroundcheckPage, but simplified
    final String? newStatus = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: const Text('Pilih Status Baru'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, '1'),
              child: const Text('1. Ditemukan'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, '3'),
              child: const Text('3. Tutup'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, '4'),
              child: const Text('4. Ganda'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, '5'),
              child: const Text('5. Usaha Baru'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, '99'),
              child: const Text('99. Tidak Ditemukan'),
            ),
          ],
        );
      },
    );

    if (newStatus == null) return;

    // Show persistent snackbar or non-intrusive loading
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Menyimpan perubahan...'),
          duration: Duration(seconds: 1),
        ),
      );
    }

    try {
      final service = GroundcheckSupabaseService();
      // Use existing local records instead of reloading if possible,
      // but for safety we load fresh then merge
      final localRecords = await service.loadLocalRecords();
      final updatedRecords = <GroundcheckRecord>[];
      final Map<String, GroundcheckRecord> updatedMap = Map.from(_localDataMap);

      // Update records in memory
      final recordsToSync = <GroundcheckRecord>[];
      for (var record in localRecords) {
        // Check if this record is selected (by perusahaanId or idsbr)
        if (_selectedIds.contains(record.perusahaanId) ||
            _selectedIds.contains(record.idsbr)) {
          // Logic: Skip if uploaded and status is same
          if (record.isUploaded && record.gcsResult == newStatus) {
            updatedRecords.add(record);
            continue;
          }

          // Logic isUploaded: If uploaded, set false and mark as revisi
          final bool wasUploaded = record.isUploaded;
          final updated = record.copyWith(
            gcsResult: newStatus,
            isUploaded: wasUploaded ? false : record.isUploaded,
            isRevisi: wasUploaded ? true : record.isRevisi,
          );

          updatedRecords.add(updated);
          recordsToSync.add(updated);

          // Update local map directly
          if (updated.perusahaanId.isNotEmpty) {
            updatedMap[updated.perusahaanId.trim()] = updated;
          }
          if (updated.idsbr.isNotEmpty) {
            updatedMap[updated.idsbr.trim()] = updated;
          }
        } else {
          updatedRecords.add(record);
        }
      }

      // Sync to Supabase
      if (recordsToSync.isNotEmpty) {
        await service.upsertRecords(recordsToSync);
      }

      // Save back to local storage
      await service.saveLocalRecords(updatedRecords);

      if (mounted) {
        setState(() {
          _localDataMap = updatedMap;
          _selectedIds.clear(); // Clear selection
          // No global isLoading trigger to prevent scroll reset
        });

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status berhasil diperbarui')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal memperbarui status: $e')));
      }
    }
  }

  String _cleanAddressForGoogleMaps(String address) {
    final rtRwRegex = RegExp(
      r'\b(rt|rw)\b[.\s/-]*[\d-]*',
      caseSensitive: false,
    );
    String cleaned = address.replaceAll(rtRwRegex, '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'[,/.-]\s*[,/.-]'), ',');
    cleaned = cleaned.replaceAll(RegExp(r'^[\s,./-]+|[\s,./-]+$'), '');
    return cleaned.trim();
  }

  Future<_GeocodeResult?> _geocodeAddress(String address) async {
    const apiKey = 'AIzaSyDnmzg1NGiODI5clNzFd0G3SkpQm_HavUE';
    try {
      String searchAddress = address;
      if (!searchAddress.toLowerCase().contains('parepare')) {
        searchAddress = '$searchAddress, Parepare';
      }
      searchAddress = '$searchAddress, Sulawesi Selatan, Indonesia';

      final url = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': searchAddress,
        'components': 'locality:Parepare|country:ID',
        'key': apiKey,
      });

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK') {
          final results = data['results'] as List;
          if (results.isNotEmpty) {
            final location = results[0]['geometry']['location'];
            final viewport = results[0]['geometry']['viewport'];
            return _GeocodeResult(
              LatLng(location['lat'], location['lng']),
              viewportNE: viewport != null
                  ? LatLng(
                      viewport['northeast']['lat'],
                      viewport['northeast']['lng'],
                    )
                  : null,
              viewportSW: viewport != null
                  ? LatLng(
                      viewport['southwest']['lat'],
                      viewport['southwest']['lng'],
                    )
                  : null,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[Geocoding] Error: $e');
    }
    return null;
  }

  Future<void> _handleBulkDeleteNew() async {
    final selectedIds = _selectedIds.toList();
    if (selectedIds.isEmpty) return;

    // Filter only TEMP- records
    final tempIds = <String>[];
    for (var id in selectedIds) {
      final rec =
          _localDataMap[id] ??
          _localDataMap[id.replaceAll(RegExp(r'[^0-9]'), '')];

      // Use resolved record ID or the selection ID itself if it looks like TEMP-
      if (rec != null) {
        if (rec.idsbr.toUpperCase().startsWith('TEMP-')) {
          tempIds.add(rec.idsbr);
        } else if (rec.perusahaanId.toUpperCase().startsWith('TEMP-')) {
          tempIds.add(rec.perusahaanId);
        }
      } else if (id.toUpperCase().startsWith('TEMP-')) {
        tempIds.add(id);
      }
    }

    if (tempIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada data baru (TEMP-) yang dipilih.'),
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Data Baru'),
        content: Text(
          'Yakin ingin menghapus ${tempIds.length} data baru yang dipilih?\n'
          'Data akan dihapus dari server dan lokal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Show simple loading dialog since we don't have _isDeletingNew state variable in this page
      // or we can just use the global isLoading
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final service = GroundcheckSupabaseService();
      final success = await service.deleteRecords(tempIds);

      if (!mounted) return;
      Navigator.pop(context); // Pop loading

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data berhasil dihapus'),
            backgroundColor: Colors.green,
          ),
        );

        setState(() {
          // Remove deleted records from local map directly to avoid reload/refresh
          for (final id in tempIds) {
            final record = _localDataMap[id];
            if (record != null) {
              if (record.idsbr.isNotEmpty) {
                _localDataMap.remove(record.idsbr.trim());
              }
              if (record.perusahaanId.isNotEmpty) {
                _localDataMap.remove(record.perusahaanId.trim());
              }
            } else {
              _localDataMap.remove(id);
            }
          }
          _selectedIds.clear();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal menghapus data'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleBulkGeocoding() async {
    if (_selectedIds.isEmpty) return;

    final records = <GroundcheckRecord>[];
    for (var id in _selectedIds) {
      final rec =
          _localDataMap[id] ??
          _localDataMap[id.replaceAll(RegExp(r'[^0-9]'), '')];
      if (rec != null) {
        records.add(rec);
      }
    }

    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada data lokal yang valid untuk data terpilih.'),
        ),
      );
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Geocoding'),
        content: Text(
          'Akan melakukan geocoding untuk ${records.length} data terpilih. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ya'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Sedang memproses geocoding...'),
              ],
            ),
          ),
        ),
      ),
    );

    int successCount = 0;
    int failCount = 0;
    final updatedRecords = <GroundcheckRecord>[];
    final Map<String, GroundcheckRecord> updatedMap = Map.from(_localDataMap);

    // Reload local records to ensure we have latest data to update
    final service = GroundcheckSupabaseService();
    final localRecords = await service.loadLocalRecords();

    // Create map for fast lookup of loaded records
    final localRecordsMap = <String, GroundcheckRecord>{};
    for (var r in localRecords) {
      if (r.perusahaanId.isNotEmpty) localRecordsMap[r.perusahaanId.trim()] = r;
      if (r.idsbr.isNotEmpty) localRecordsMap[r.idsbr.trim()] = r;
    }

    for (var record in records) {
      // Find the latest version of this record
      final latestRecord =
          localRecordsMap[record.perusahaanId.trim()] ??
          localRecordsMap[record.idsbr.trim()] ??
          record;

      if (latestRecord.alamatUsaha.isEmpty) {
        failCount++;
        continue;
      }

      final cleanedAddress = _cleanAddressForGoogleMaps(
        latestRecord.alamatUsaha,
      );
      final result = await _geocodeAddress(cleanedAddress);

      if (result != null) {
        final updated = latestRecord.copyWith(
          latitude: result.location.latitude.toString(),
          longitude: result.location.longitude.toString(),
        );
        updatedRecords.add(updated);

        // Update map immediately for UI
        if (updated.perusahaanId.isNotEmpty) {
          updatedMap[updated.perusahaanId.trim()] = updated;
        }
        if (updated.idsbr.isNotEmpty) {
          updatedMap[updated.idsbr.trim()] = updated;
        }

        successCount++;
      } else {
        failCount++;
      }

      // Delay to respect rate limits
      await Future.delayed(const Duration(milliseconds: 200));
    }

    // Sync to Supabase
    if (updatedRecords.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Menyimpan koordinat ke database...'),
          duration: Duration(seconds: 1),
        ),
      );
      await service.upsertRecords(updatedRecords);
    }

    // Merge updates into localRecords list to save
    final finalRecordsToSave = <GroundcheckRecord>[];
    final processedIds =
        <String>{}; // Track processed IDs to avoid duplicates if any

    // First, add all updated records
    for (var r in updatedRecords) {
      finalRecordsToSave.add(r);
      if (r.perusahaanId.isNotEmpty) processedIds.add(r.perusahaanId.trim());
      if (r.idsbr.isNotEmpty) processedIds.add(r.idsbr.trim());
    }

    // Then add remaining original records
    for (var r in localRecords) {
      final pid = r.perusahaanId.trim();
      final sid = r.idsbr.trim();
      if ((pid.isEmpty || !processedIds.contains(pid)) &&
          (sid.isEmpty || !processedIds.contains(sid))) {
        finalRecordsToSave.add(r);
      }
    }

    await service.saveLocalRecords(finalRecordsToSave);

    if (mounted) {
      Navigator.pop(context); // Close progress dialog
      setState(() {
        _localDataMap = updatedMap;
        _selectedIds.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Geocoding selesai: $successCount berhasil, $failCount gagal',
          ),
        ),
      );
    }
  }

  Widget _buildStatusChip(String? gcsResult) {
    String label = 'Belum GC';
    Color color = Colors.grey;
    String code = '';

    if (gcsResult != null) {
      final lower = gcsResult.toLowerCase();
      if (lower == '1' || lower.contains('ditemukan')) {
        label = 'Ditemukan';
        code = '1';
        color = Colors.green;
      } else if (lower == '3' || lower.contains('tutup')) {
        label = 'Tutup';
        code = '3';
        color = Colors.blueGrey;
      } else if (lower == '4' || lower.contains('ganda')) {
        label = 'Ganda';
        code = '4';
        color = Colors.orange;
      } else if (lower == '5' || lower.contains('usaha baru')) {
        label = 'Usaha Baru';
        code = '5';
        color = Colors.blue;
      } else if (lower == '99' || lower.contains('tidak ditemukan')) {
        label = 'Tidak Ditemukan';
        code = '99';
        color = Colors.red;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        code.isNotEmpty ? '$code. $label' : label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Color _getGroupStatusColor(DuplicateGroup group) {
    int countFound = 0;
    int countNull = 0;
    int countNewValid = 0;
    int countActive = 0;

    for (var record in group.records) {
      // Logic lookup same as in DataTable
      final localRecord =
          _localDataMap[record.perusahaanId.trim()] ??
          _localDataMap[record.perusahaanId.replaceAll(RegExp(r'[^0-9]'), '')];

      // If localRecord is null, it means it's deleted/missing.
      // We skip it for status calculation.
      if (localRecord == null) continue;

      countActive++;
      final status = localRecord.gcsResult;
      final idsbr = localRecord.idsbr.toUpperCase();

      // Normalize status string
      final lower = status.toLowerCase().trim();

      // Check for empty or "null" string explicitly
      if (lower.isEmpty || lower == 'null') {
        countNull++;
      } else {
        // Check for '1' or 'ditemukan'
        if (lower == '1' || lower.contains('ditemukan')) {
          countFound++;
        }
        // Check for '5' or 'usaha baru' or IDSBR starts with TEMP
        if (lower == '5' ||
            lower.contains('usaha baru') ||
            idsbr.startsWith('TEMP')) {
          countNewValid++;
        }
      }
    }

    // Logic Rules:

    // 0. If all records are deleted?
    if (countActive == 0) {
      return Colors.grey.shade300;
    }

    // 1. Grey: countNull > 0 (User: "klo ada yg blm GC ... harus nya abu2")
    // Prioritize "Unfinished" state over "Found" state.
    if (countNull > 0) {
      return Colors.white; // Default card color (represents Grey/Pending)
    }

    // NEW RULE: Blue
    // "jika ada dalam group yg isinya idsbr baru atau 'temp-' atau hasil gcs 5 baru.
    // ketika salah satu dihapus. kan tinggal satu baru ... jadi baru valid (warna biru)."
    if (countActive == 1 && countNewValid == 1) {
      return Colors.blue.shade100;
    }

    // 2. Green: countFound == 1 AND countNull == 0 (User: "status GC kode 1 ... dan sisanya selain kode 1 ... dianggap benar")
    if (countFound == 1) {
      return Colors.green.shade100;
    }

    // 3. Red: (countFound == 0 OR countFound > 1) AND countNull == 0
    // - 0 found: "status lengkap tapi nda ada kode 1"
    // - >1 found: Conflict
    return Colors.red.shade100;
  }

  Widget _buildStatusPerusahaanChip(String? statusPerusahaan) {
    if (statusPerusahaan == null || statusPerusahaan.isEmpty) {
      return const Text('-');
    }

    // Parse status code if format is "1. Aktif" or just "1"
    final codeMatch = RegExp(r'^\s*(\d+)').firstMatch(statusPerusahaan);
    int? code = codeMatch != null ? int.tryParse(codeMatch.group(1)!) : null;

    final Map<int, String> statusMap = {
      1: 'Aktif',
      2: 'Tutup Sementara',
      3: 'Belum Beroperasi',
      4: 'Tutup',
      5: 'Alih Usaha',
      6: 'Tidak Ditemukan',
      7: 'Aktif Pindah',
      8: 'Aktif Nonrespon',
      9: 'Duplikat',
      10: 'Salah Kode Wilayah',
    };

    String label = statusPerusahaan;
    Color color = Colors.grey;

    if (code != null && statusMap.containsKey(code)) {
      label = '$code. ${statusMap[code]}';
      switch (code) {
        case 1:
          color = Colors.green;
          break;
        case 2:
          color = Colors.amber;
          break;
        case 3:
          color = Colors.blue;
          break;
        case 4:
          color = Colors.red;
          break;
        case 5:
          color = Colors.deepPurple;
          break;
        case 6:
          color = Colors.red;
          break;
        case 7:
          color = Colors.teal;
          break;
        case 8:
          color = Colors.orange;
          break;
        case 9:
          color = Colors.brown;
          break;
        case 10:
          color = Colors.redAccent;
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }

    if (_groups.isEmpty) {
      return const Center(child: Text('Tidak ada data duplikasi ditemukan.'));
    }

    int totalRecords = _groups.fold(
      0,
      (sum, group) => sum + group.records.length,
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Indikasi Ganda'),
            Text(
              '${_groups.length} Grup, $totalRecords Usaha',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat Ulang Data',
            onPressed: () {
              setState(() {
                _isLoading = true;
              });
              _loadData();
            },
          ),
        ],
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      floatingActionButton: _selectedIds.isNotEmpty
          ? Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_selectedIds.length == 1) ...[
                  FloatingActionButton.extended(
                    heroTag: 'fab_group_resolve',
                    onPressed: _handleBulkGroupResolve,
                    icon: const Icon(Icons.done_all),
                    label: const Text('Tetapkan Valid & Ganda'),
                    backgroundColor: Colors.purple,
                  ),
                  const SizedBox(width: 16),
                ],
                // Show Delete button if any selected item starts with TEMP-
                if (_selectedIds.any(
                  (id) =>
                      id.toUpperCase().startsWith('TEMP-') ||
                      ((_localDataMap[id]?.idsbr.toUpperCase().startsWith(
                            'TEMP-',
                          ) ??
                          false)),
                )) ...[
                  FloatingActionButton.extended(
                    heroTag: 'fab_delete_new',
                    onPressed: _handleBulkDeleteNew,
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('Hapus Baru'),
                    backgroundColor: Colors.red[900],
                  ),
                  const SizedBox(width: 16),
                ],
                FloatingActionButton.extended(
                  heroTag: 'fab_deselect',
                  onPressed: () {
                    setState(() {
                      _selectedIds.clear();
                    });
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Batal Pilih'),
                  backgroundColor: Colors.grey,
                ),
                const SizedBox(width: 16),
                FloatingActionButton.extended(
                  heroTag: 'fab_geocode',
                  onPressed: _handleBulkGeocoding,
                  icon: const Icon(Icons.map),
                  label: const Text('Geocoding'),
                  backgroundColor: Colors.teal,
                ),
                const SizedBox(width: 16),
                if (!_selectedIds.any((id) {
                  final rec =
                      _localDataMap[id] ??
                      _localDataMap[id.replaceAll(RegExp(r'[^0-9]'), '')];
                  final idsbr = rec?.idsbr ?? id;
                  final status = rec?.gcsResult ?? '';
                  return idsbr.toUpperCase().startsWith('TEMP-') ||
                      status == '5' ||
                      status.toLowerCase().contains('usaha baru');
                }))
                  FloatingActionButton.extended(
                    heroTag: 'fab_bulk_edit_duplicate',
                    onPressed: _handleBulkEditStatus,
                    icon: const Icon(Icons.edit),
                    label: Text('Ubah Status (${_selectedIds.length})'),
                    backgroundColor: Colors.orange,
                  ),
              ],
            )
          : null,
      body: ListView.builder(
        itemCount: _groups.length,
        itemBuilder: (context, index) {
          final group = _groups[index];
          final firstRecord = group.records.isNotEmpty
              ? group.records.first
              : null;
          final confidence = firstRecord?.confidenceScore ?? 'N/A';
          final reasoning = firstRecord?.reasoning ?? '';

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: _getGroupStatusColor(group),
            child: ExpansionTile(
              title: Text(
                'Group ${group.groupId}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Confidence: $confidence%\n$reasoning',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: DataTable(
                          columnSpacing: 16,
                          headingRowColor: MaterialStateProperty.all(
                            Colors.grey.shade50,
                          ),
                          columns: const [
                            DataColumn(label: Text('IDSBR')),
                            DataColumn(label: Text('Nama Usaha')),
                            DataColumn(label: Text('Alamat')),
                            DataColumn(label: Text('Kode Wilayah')),
                            DataColumn(label: Text('Status Perusahaan')),
                            DataColumn(label: Text('Skala')),
                            DataColumn(label: Text('Sumber')),
                            DataColumn(label: Text('Status GC')),
                            DataColumn(label: Text('Uploaded')),
                            DataColumn(label: Text('Koordinat')),
                          ],
                          rows: group.records.map((record) {
                            // Try to find local record
                            final localRecord =
                                _localDataMap[record.perusahaanId] ??
                                _localDataMap[record.perusahaanId.replaceAll(
                                  RegExp(r'[^0-9]'),
                                  '',
                                )];

                            final displayNama =
                                localRecord?.namaUsaha.isNotEmpty == true
                                ? localRecord!.namaUsaha
                                : (localRecord == null
                                      ? '${record.namaUsaha} (Terhapus)'
                                      : record.namaUsaha);

                            final displayAlamat =
                                localRecord?.alamatUsaha.isNotEmpty == true
                                ? localRecord!.alamatUsaha
                                : record.alamat;

                            // Style for deleted/missing records
                            final isMissing = localRecord == null;
                            final textStyle = isMissing
                                ? const TextStyle(
                                    color: Colors.grey,
                                    decoration: TextDecoration.lineThrough,
                                    fontStyle: FontStyle.italic,
                                  )
                                : null;

                            final gcsResult = localRecord?.gcsResult;
                            final idsbr =
                                localRecord?.idsbr ?? record.perusahaanId;
                            final kodeWilayah = localRecord?.kodeWilayah ?? '-';
                            final statusPerusahaan =
                                localRecord?.statusPerusahaan;
                            final skalaUsaha = localRecord?.skalaUsaha ?? '-';
                            final sumberData = localRecord?.sumberData ?? '-';

                            // Determine ID for selection (prefer perusahaanId/idsbr from local if avail)
                            final selectionId =
                                localRecord?.perusahaanId.isNotEmpty == true
                                ? localRecord!.perusahaanId
                                : (localRecord?.idsbr.isNotEmpty == true
                                      ? localRecord!.idsbr
                                      : record.perusahaanId);

                            final isSelected = _selectedIds.contains(
                              selectionId,
                            );

                            bool hasCoordinates = false;
                            if (localRecord != null) {
                              final lat = localRecord.latitude.trim();
                              final lon = localRecord.longitude.trim();
                              if (lat.isNotEmpty &&
                                  lat != '0' &&
                                  lat != '0.0' &&
                                  lat != 'null' &&
                                  lon.isNotEmpty &&
                                  lon != '0' &&
                                  lon != '0.0' &&
                                  lon != 'null') {
                                hasCoordinates = true;
                              }
                            }

                            return DataRow(
                              selected: isSelected,
                              onSelectChanged: (selected) {
                                setState(() {
                                  if (selected == true) {
                                    _selectedIds.add(selectionId);
                                  } else {
                                    _selectedIds.remove(selectionId);
                                  }
                                });
                              },
                              cells: [
                                DataCell(
                                  Text(
                                    idsbr,
                                    style: isMissing
                                        ? textStyle
                                        : const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 200,
                                    child: Text(
                                      displayNama,
                                      style: isMissing
                                          ? textStyle
                                          : const TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 200,
                                    child: Text(
                                      displayAlamat,
                                      style: textStyle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(Text(kodeWilayah)),
                                DataCell(
                                  _buildStatusPerusahaanChip(statusPerusahaan),
                                ),
                                DataCell(Text(skalaUsaha)),
                                DataCell(Text(sumberData)),
                                DataCell(_buildStatusChip(gcsResult)),
                                DataCell(
                                  localRecord?.isUploaded == true
                                      ? const Icon(
                                          Icons.cloud_done,
                                          color: Colors.green,
                                        )
                                      : (localRecord?.isRevisi == true
                                            ? const Icon(
                                                Icons.warning,
                                                color: Colors.orange,
                                              )
                                            : const Icon(
                                                Icons.cloud_off,
                                                color: Colors.grey,
                                              )),
                                ),
                                DataCell(
                                  hasCoordinates
                                      ? Tooltip(
                                          message: 'Ada Koordinat - Lihat Peta',
                                          child: IconButton(
                                            icon: const Icon(
                                              Icons.location_on,
                                              color: Colors.green,
                                            ),
                                            onPressed: () {
                                              if (localRecord != null &&
                                                  widget.onGoToMap != null) {
                                                widget.onGoToMap!(localRecord);
                                              }
                                            },
                                          ),
                                        )
                                      : const Tooltip(
                                          message: 'Tidak Ada Koordinat',
                                          child: Icon(
                                            Icons.location_off,
                                            color: Colors.grey,
                                          ),
                                        ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
