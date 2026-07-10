import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/services/anomali_pusat_import_service.dart';

class ImportAnomaliPusatPage extends StatefulWidget {
  const ImportAnomaliPusatPage({super.key});

  @override
  State<ImportAnomaliPusatPage> createState() => _ImportAnomaliPusatPageState();
}

class _ImportAnomaliPusatPageState extends State<ImportAnomaliPusatPage> {
  final AnomaliPusatImportService _service = AnomaliPusatImportService();

  final List<ParsedAnomaliPusatFile> _files = [];
  final List<String> _parseErrors = [];
  AnomaliPusatImportMode _mode = AnomaliPusatImportMode.refresh;
  bool _isParsing = false;
  bool _isUploading = false;
  List<AnomaliPusatImportResult>? _results;
  final List<String> _uploadErrors = [];

  bool _isComparing = false;
  String? _compareError;
  Map<String, AnomaliPusatCompareResult>? _comparison;

  static const Map<String, String> _fieldLabels = {
    'status_aktif': 'Status',
    'nama_provinsi': 'Nama provinsi',
    'nama_kab': 'Nama kab/kota',
    'kode_kec': 'Kode kecamatan',
    'nama_kec': 'Nama kecamatan',
    'kode_desa': 'Kode desa',
    'nama_desa': 'Nama desa/kel',
    'kode_sls': 'Kode SLS',
    'sub_sls': 'Sub SLS',
    'kategori_nama': 'Nama kategori',
    'status_asal': 'Tindak lanjut',
    'id_petugas': 'ID petugas',
    'email_petugas': 'Email petugas',
    'link_fasih': 'Link Fasih',
  };

  Future<void> _pickFiles() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
      allowMultiple: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    setState(() {
      _isParsing = true;
      _files.clear();
      _parseErrors.clear();
      _results = null;
      _uploadErrors.clear();
      _comparison = null;
      _compareError = null;
    });

    for (final f in picked.files) {
      final bytes = f.bytes;
      if (bytes == null) {
        _parseErrors.add('${f.name}: gagal membaca file.');
        continue;
      }
      try {
        _files.add(_service.parseFile(f.name, bytes));
      } catch (e) {
        _parseErrors.add('${f.name}: $e');
      }
    }

    if (!mounted) return;
    setState(() => _isParsing = false);
  }

  /// Label 1 scope untuk hasil/error: "Usaha (fileA.xlsx, fileB.xlsx)".
  String _scopeUploadLabel(String scope) {
    final names =
        _files.where((f) => f.scope == scope).map((f) => f.fileName).join(', ');
    return '${_scopeLabel(scope)} ($names)';
  }

  Future<void> _compare() async {
    if (_files.isEmpty) return;

    setState(() {
      _isComparing = true;
      _compareError = null;
      _comparison = null;
    });

    final comparison = <String, AnomaliPusatCompareResult>{};
    String? error;
    final grouped = AnomaliPusatImportService.gabungkanRowsPerScope(_files);
    for (final entry in grouped.entries) {
      try {
        comparison[entry.key] =
            await _service.compareRows(scope: entry.key, rows: entry.value);
      } catch (e) {
        error = '${_scopeUploadLabel(entry.key)}: gagal membandingkan -- $e';
        break;
      }
    }

    if (!mounted) return;
    setState(() {
      _isComparing = false;
      _compareError = error;
      _comparison = error == null ? comparison : null;
    });
  }

  Future<void> _upload() async {
    if (_files.isEmpty) return;

    setState(() {
      _isUploading = true;
      _results = null;
      _uploadErrors.clear();
    });

    final results = <AnomaliPusatImportResult>[];
    // Semua file dengan scope sama digabung jadi 1 batch. Kalau dikirim per
    // file, mode refresh/replace akan menonaktifkan/menghapus baris dari file
    // sebelumnya karena server menganggapnya "tidak ada di file".
    final grouped = AnomaliPusatImportService.gabungkanRowsPerScope(_files);
    for (final entry in grouped.entries) {
      final label = _scopeUploadLabel(entry.key);
      try {
        final result = await _service.importRows(
          scope: entry.key,
          label: label,
          rows: entry.value,
          mode: _mode,
        );
        results.add(result);
      } catch (e) {
        _uploadErrors.add('$label: gagal diunggah -- $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _results = results;
      _isUploading = false;
      // Database sudah berubah -- hasil perbandingan lama tidak berlaku lagi.
      _comparison = null;
    });
  }

  String _scopeLabel(String scope) => scope == 'usaha' ? 'Usaha' : 'Keluarga';

  Color _scopeColor(String scope) =>
      scope == 'usaha' ? const Color(0xFFB31E63) : const Color(0xFF1F6FEB);

  @override
  Widget build(BuildContext context) {
    final totalRows = _files.fold<int>(0, (sum, f) => sum + f.rows.length);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: const Text('Impor Anomali Pusat'),
        backgroundColor: const Color(0xFF1F6FEB),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Pilih satu atau beberapa file export "Data Mikro Kasus '
              'Anomali" dari Fasih (usaha maupun keluarga boleh sekaligus '
              '-- jenisnya dideteksi otomatis). Cek pratinjaunya, '
              'bandingkan dengan database untuk melihat apa saja yang '
              'berubah, pilih cara memperlakukan data lama, lalu unggah.',
              style: TextStyle(color: Colors.blueGrey, height: 1.5),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _isParsing || _isUploading ? null : _pickFiles,
              icon: const Icon(Icons.upload_file_rounded),
              label: Text(
                _files.isEmpty && _parseErrors.isEmpty
                    ? 'Pilih file Excel (.xlsx)'
                    : 'Ganti file',
              ),
            ),
            if (_isParsing) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_parseErrors.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDECEC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _parseErrors
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            e,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
            if (_files.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Pratinjau -- ${_files.length} file, $totalRows baris total',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              ..._files.map(_buildFilePreviewCard),
              const SizedBox(height: 24),
              const Text(
                'Perubahan dibanding database',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Opsional: cek dulu apa saja yang baru, berubah, atau hilang '
                'dari file ini sebelum mengunggah. Tidak mengubah data.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blueGrey[600],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed:
                    _isComparing || _isUploading || _isParsing ? null : _compare,
                icon: const Icon(Icons.compare_arrows_rounded),
                label: Text(
                  _comparison == null
                      ? 'Bandingkan dengan database'
                      : 'Bandingkan ulang',
                ),
              ),
              if (_isComparing) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_compareError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDECEC),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _compareError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
              if (_comparison != null) ...[
                const SizedBox(height: 12),
                ..._comparison!.values.map(_buildCompareScopeCard),
              ],
              const SizedBox(height: 24),
              const Text(
                'Data lama yang tidak ada di file ini',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              _buildModeSelector(),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isUploading ? null : _upload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F6FEB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _isUploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_upload_rounded),
                  label: Text(
                    _isUploading
                        ? 'Mengunggah...'
                        : 'Konversi & Upload ke Database',
                  ),
                ),
              ),
            ],
            if (_uploadErrors.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDECEC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _uploadErrors
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            e,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
            if (_results != null) ...[
              const SizedBox(height: 16),
              ..._results!.map(_buildResultCard),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    int? hilangAktif;
    int? hilangTotal;
    if (_comparison != null) {
      hilangAktif =
          _comparison!.values.fold(0, (sum, c) => sum! + c.hilangAktif);
      hilangTotal =
          _comparison!.values.fold(0, (sum, c) => sum! + c.countOf('hilang'));
    }

    final options = [
      (
        AnomaliPusatImportMode.refresh,
        'Segarkan',
        'Nonaktifkan sementara kasus lama yang tidak ada di file ini. '
            'Aktif lagi otomatis kalau muncul lagi nanti. Paling aman.'
            '${hilangAktif != null ? '\nBerdasarkan perbandingan: $hilangAktif kasus akan dinonaktifkan.' : ''}',
      ),
      (
        AnomaliPusatImportMode.tambahkan,
        'Tambahkan saja',
        'Jangan ubah data lama sama sekali, cuma tambah/perbarui yang ada '
            'di file ini.'
            '${hilangTotal != null ? '\nBerdasarkan perbandingan: $hilangTotal kasus lama dibiarkan apa adanya.' : ''}',
      ),
      (
        AnomaliPusatImportMode.replace,
        'Ganti total',
        'Hapus permanen kasus lama yang tidak ada di file ini. Keterangan '
            'petugas yang sudah ditulis tetap tersimpan.'
            '${hilangTotal != null ? '\nBerdasarkan perbandingan: $hilangTotal kasus akan dihapus permanen.' : ''}',
      ),
    ];

    return Column(
      children: options.map((opt) {
        final (mode, title, desc) = opt;
        final selected = _mode == mode;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _mode = mode),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF1F6FEB)
                      : Colors.grey.withValues(alpha: 0.25),
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Radio<AnomaliPusatImportMode>(
                    value: mode,
                    groupValue: _mode,
                    onChanged: (v) => setState(() => _mode = v!),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            desc,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey[600],
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFilePreviewCard(ParsedAnomaliPusatFile file) {
    final color = _scopeColor(file.scope);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _files.length == 1,
          title: Text(
            file.fileName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    _scopeLabel(file.scope),
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${file.rows.length} baris',
                  style: TextStyle(color: Colors.blueGrey[500], fontSize: 12),
                ),
              ],
            ),
          ),
          children: [
            SizedBox(
              height: 320,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                itemCount: file.rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final row = file.rows[index];
                  final wilayah = [row['nama_kec'], row['nama_desa']]
                      .where((v) => v != null && (v as String).isNotEmpty)
                      .join(' / ');
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${index + 1}. ${row['nama_subjek'] ?? '-'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          wilayah.isEmpty ? '-' : wilayah,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey[600],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Kategori ${row['kategori_kode']}: ${row['kategori_nama']}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _statusMeta = {
    'baru': ('Baru', 'Belum ada di database', Color(0xFF2E7D32)),
    'berubah': ('Berubah', 'Ada di database, isinya beda', Color(0xFFEF6C00)),
    'hilang': (
      'Tidak ada di file',
      'Ada di database tapi tidak muncul di file ini',
      Color(0xFFC62828),
    ),
    'sama': ('Sama persis', 'Tidak ada perubahan', Color(0xFF546E7A)),
  };

  Widget _buildCompareScopeCard(AnomaliPusatCompareResult comparison) {
    final color = _scopeColor(comparison.scope);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  _scopeLabel(comparison.scope),
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${comparison.rows.length} kasus dibandingkan',
                style: TextStyle(color: Colors.blueGrey[500], fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _statusMeta.entries
                .map(
                  (e) => _buildCountChip(
                    e.value.$1,
                    comparison.countOf(e.key),
                    e.value.$3,
                  ),
                )
                .toList(),
          ),
          ..._statusMeta.entries
              .where((e) => e.key != 'sama')
              .map((e) => _buildCompareStatusTile(comparison, e.key)),
        ],
      ),
    );
  }

  Widget _buildCountChip(String label, int count, Color color) {
    final active = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (active ? color : Colors.blueGrey).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          color: active ? color : Colors.blueGrey,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildCompareStatusTile(
    AnomaliPusatCompareResult comparison,
    String status,
  ) {
    const maxDitampilkan = 100;
    final rows = comparison.byStatus(status);
    if (rows.isEmpty) return const SizedBox.shrink();

    final (label, desc, color) = _statusMeta[status]!;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          '$label (${rows.length})',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        subtitle: Text(
          desc,
          style: TextStyle(fontSize: 11, color: Colors.blueGrey[500]),
        ),
        children: [
          ...rows.take(maxDitampilkan).map(_buildCompareRowTile),
          if (rows.length > maxDitampilkan)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '... dan ${rows.length - maxDitampilkan} kasus lainnya',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey[500]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompareRowTile(AnomaliPusatCompareRow row) {
    final wilayah = [row.namaKec, row.namaDesa]
        .where((v) => v != null && v.isNotEmpty)
        .join(' / ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.namaSubjek +
                (row.status == 'hilang' && !row.isAktif
                    ? ' (sudah nonaktif)'
                    : ''),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            wilayah.isEmpty ? '-' : wilayah,
            style: TextStyle(fontSize: 12, color: Colors.blueGrey[600]),
          ),
          const SizedBox(height: 2),
          Text(
            'Kategori ${row.kategoriKode}: ${row.kategoriNama}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          ...row.perubahan.map(
            (p) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '- ${_fieldLabels[p.field] ?? p.field}: '
                '"${p.lama ?? '-'}" menjadi "${p.baru ?? '-'}"',
                style: const TextStyle(fontSize: 12, color: Color(0xFFEF6C00)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(AnomaliPusatImportResult result) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${result.totalBaris} baris diproses, ${result.diperbarui} kasus '
            'diperbarui/ditambahkan'
            '${result.dinonaktifkan > 0 ? ', ${result.dinonaktifkan} kasus lama dinonaktifkan sementara' : ''}'
            '${result.dihapus > 0 ? ', ${result.dihapus} kasus lama dihapus' : ''}.',
            style: const TextStyle(color: Color(0xFF1B5E20)),
          ),
        ],
      ),
    );
  }
}
