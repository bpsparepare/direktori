import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';

import '../../data/services/fasih_rekap_service.dart';
import '../../data/services/groundcheck_supabase_service.dart';
import '../../data/services/lembar_kerja_export_service.dart';

/// Lembar Kerja: progres pendataan per petugas dengan detail per SLS/sub-SLS.
///
/// - admin    : tabel semua petugas -> tabel wilayah (SLS/sub-SLS) petugas
/// - pengawas : tabel petugas binaan -> tabel wilayah petugas
/// - pendata  : langsung melihat tabel wilayah tugasnya sendiri
class LembarKerjaPage extends StatefulWidget {
  const LembarKerjaPage({super.key});

  @override
  State<LembarKerjaPage> createState() => _LembarKerjaPageState();
}

class _LembarKerjaPageState extends State<LembarKerjaPage> {
  final GroundcheckSupabaseService _profileService =
      GroundcheckSupabaseService();
  final FasihRekapService _rekapService = FasihRekapService();
  final LembarKerjaExportService _exportService = LembarKerjaExportService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isExporting = false;
  String? _error;
  Se2026UserProfile? _profile;
  FasihRekapPayload _payload = FasihRekapPayload.empty();
  FasihRekapRow? _selectedPetugas;

  /// Target prelist per wilayah (key: id wilayah 16 digit) dan
  /// agregatnya per petugas (key: id petugas/ppl_id).
  Map<String, int> _prelistByWilayah = {};
  Map<String, int> _prelistByPetugas = {};
  bool _prelistLoaded = false;

  /// Distribusi kode_bang (submitted) per wilayah 16 digit dan per petugas
  /// (ppl_id), dibangun langsung dari RPC.
  /// Status pendataan manual per wilayah (key: kode_wilayah 16 digit).
  /// [_statusByWilayah] menyimpan kode status, [_noteByWilayah] catatannya.
  Map<String, String> _statusByWilayah = {};
  Map<String, String> _noteByWilayah = {};
  bool _statusLoaded = false;
  bool _savingStatus = false;

  /// Seluruh wilayah (SLS/sub-SLS) dalam scope pengguna, dikelompokkan per
  /// petugas. Dimuat sekali saat tab Status dibuka di level petugas — agar
  /// rekap status umum & per petugas terlihat tanpa membuka tiap petugas.
  List<_PetugasWilayahGroup>? _allWilayahGroups;
  bool _allWilayahLoading = false;

  /// Filter tab Status: hanya tampilkan wilayah dgn kode status ini. Nilai
  /// khusus [_belumTandaKey] = wilayah belum ditandai. null = semua.
  String? _statusFilter;
  static const String _belumTandaKey = '__BELUM__';

  /// Sort tab Status (terpisah untuk tiap tabel; indeks sesuai header).
  int? _statusPetugasSortCol;
  bool _statusPetugasAsc = true;
  int? _statusSlsSortCol;
  bool _statusSlsAsc = true;

  /// Seluruh baris wilayah (flatten dari [_allWilayahGroups]).
  List<FasihRekapRow> get _allWilayahFlat => _allWilayahGroups == null
      ? const []
      : [for (final g in _allWilayahGroups!) ...g.wilayah];

  /// Tab tabel: 0 = Progres, 1 = Jenis Bangunan (kode_bang).
  int _tableTab = 0;

  /// Filter tabel berdasarkan kategori sebaran (indeks _tiers). null = semua.
  int? _selectedTier;

  /// Data tab Pengawas (khusus admin, dimuat saat tab dibuka).
  FasihRekapPayload? _pengawasPayload;
  bool _pengawasLoading = false;
  Map<String, int> _prelistByPengawas = {};

  /// Data tab Riil (progres_sls_harian), dimuat saat tab dibuka.
  Map<String, _Riil> _riilByWilayah = {};
  Map<String, _Riil> _riilByPetugas = {};
  bool _riilLoaded = false;
  bool _riilLoading = false;

  /// State sort tabel. null = urutan default (per kode wilayah / dari server).
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _role => _profile?.role ?? '';

  bool get _isPetugasLevel =>
      (_role == 'admin' || _role == 'pengawas') && _selectedPetugas == null;

  /// Muat ulang penuh (dipakai pull-to-refresh): paksa ambil ulang target
  /// prelist, progres riil, dan status pendataan — bukan hanya tabel progres —
  /// agar perubahan dari petugas lain langsung terlihat.
  Future<void> _refreshAll() async {
    _prelistLoaded = false;
    _riilLoaded = false;
    _statusLoaded = false;
    _pengawasPayload = null;
    _allWilayahGroups = null;
    await _loadData();
    // Tab Pengawas punya sumber baris sendiri; muat ulang bila sedang dibuka.
    if (mounted && _tableTab == 3) await _loadPengawas();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final profile =
          _profile ?? await _profileService.fetchCurrentSe2026Profile();
      if (profile == null) {
        throw Exception('Profil petugas SE2026 tidak ditemukan.');
      }

      final payloadFuture = _fetchPayload(profile);
      final preFutures = <Future<void>>[];
      if (!_prelistLoaded) preFutures.add(_loadPrelistTargets(profile));
      if (!_riilLoaded) preFutures.add(_loadRiil());
      if (!_statusLoaded) preFutures.add(_loadStatusPendataan());
      if (preFutures.isNotEmpty) await Future.wait(preFutures);
      final payload = await payloadFuture;
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _payload = payload;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<FasihRekapPayload> _fetchPayload(Se2026UserProfile profile) {
    final search = _searchController.text;
    final role = profile.role;

    // Sumber terpadu get_fasih_rekap (berbasis snapshot rekap). Level ditentukan
    // server dari role + parameter petugasId/allPetugas.
    if (role == 'pendata') {
      return _rekapService.fetchRekap(search: search, limit: 300);
    }
    if (_selectedPetugas != null) {
      // Drill ke wilayah (SLS) petugas terpilih → *_wilayah.
      return _rekapService.fetchRekap(
        petugasId: _selectedPetugas!.unitId,
        search: search,
        limit: 300,
      );
    }
    if (role == 'admin') {
      // Daftar semua petugas → admin_petugas.
      return _rekapService.fetchRekap(
        allPetugas: true,
        search: search,
        limit: 300,
        sortBy: 'title',
        sortDir: 'asc',
      );
    }
    if (role == 'pengawas') {
      // Daftar petugas binaan → pengawas_petugas.
      return _rekapService.fetchRekap(
        search: search,
        limit: 150,
        sortBy: 'title',
        sortDir: 'asc',
      );
    }
    return Future.value(FasihRekapPayload.empty());
  }

  Future<void> _loadPrelistTargets(Se2026UserProfile profile) async {
    final records = await _rekapService.fetchPrelistTargets(
      pmlId: profile.role == 'pengawas' ? profile.petugasId : null,
      pplId: profile.role == 'pendata' ? profile.petugasId : null,
    );
    final byWilayah = <String, int>{};
    final byPetugas = <String, int>{};
    final byPengawas = <String, int>{};
    for (final record in records) {
      if (record.id.isNotEmpty) {
        byWilayah[record.id] = (byWilayah[record.id] ?? 0) + record.prelist;
      }
      if (record.pplId.isNotEmpty) {
        byPetugas[record.pplId] =
            (byPetugas[record.pplId] ?? 0) + record.prelist;
      }
      if (record.pmlId.isNotEmpty) {
        byPengawas[record.pmlId] =
            (byPengawas[record.pmlId] ?? 0) + record.prelist;
      }
    }
    _prelistByWilayah = byWilayah;
    _prelistByPetugas = byPetugas;
    _prelistByPengawas = byPengawas;
    _prelistLoaded = true;
  }

  /// Muat rekap per pengawas (untuk tab Pengawas, khusus admin).
  Future<void> _loadPengawas() async {
    if (_pengawasLoading) return;
    setState(() => _pengawasLoading = true);
    try {
      // Admin tanpa parameter → level admin_pengawas (daftar pengawas).
      final payload = await _rekapService.fetchRekap(
        limit: 200,
        sortBy: 'title',
        sortDir: 'asc',
      );
      if (!mounted) return;
      setState(() {
        _pengawasPayload = payload;
        _pengawasLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _pengawasLoading = false);
    }
  }

  /// Muat progres riil (tab Riil). Bangun agregat per wilayah & per petugas.
  Future<void> _loadRiil() async {
    if (_riilLoading) return;
    setState(() => _riilLoading = true);
    final rows = await _rekapService.fetchProgresSlsByWilayah();
    final byW = <String, _Riil>{};
    final byP = <String, _Riil>{};
    for (final r in rows) {
      if (r.kodeWilayah.isNotEmpty) {
        (byW[r.kodeWilayah] ??= _Riil()).add(r);
      }
      if (r.pplId.isNotEmpty) {
        (byP[r.pplId] ??= _Riil()).add(r);
      }
    }
    if (!mounted) return;
    setState(() {
      _riilByWilayah = byW;
      _riilByPetugas = byP;
      _riilLoaded = true;
      _riilLoading = false;
    });
  }

  _Riil _riilForRow(FasihRekapRow row) {
    final m = _isPetugasLevel ? _riilByPetugas : _riilByWilayah;
    return m[row.unitId] ?? _Riil();
  }

  /// Jumlah APPROVED dari rincian status (alias mengandung APPROV).
  static int _approvedOf(Map<String, int> statusCounts) {
    var approved = 0;
    statusCounts.forEach((alias, count) {
      if (alias.toUpperCase().contains('APPROV')) approved += count;
    });
    return approved;
  }

  /// Approved+: semua status dijumlah KECUALI OPEN, DRAFT, dan
  /// SUBMITTED BY PENCACAH.
  static int _approvedPlusOf(Map<String, int> statusCounts) {
    var total = 0;
    statusCounts.forEach((alias, count) {
      final upper = alias.toUpperCase();
      final isOpen = upper.startsWith('OPEN');
      final isDraft = upper.startsWith('DRAFT');
      final isSubmitPencacah =
          upper.contains('SUBMIT') && upper.contains('PENCACAH');
      if (!isOpen && !isDraft && !isSubmitPencacah) total += count;
    });
    return total;
  }

  // ---------------------------------------------------------------------
  // Status pendataan manual per wilayah (SLS/sub-SLS).
  // ---------------------------------------------------------------------

  /// Urutan & kode status yang tersedia.
  static const List<String> _statusOrder = [
    'BELUM',
    'P30',
    'P50',
    'P70',
    'P90',
    'SELESAI',
  ];

  /// Label singkat status untuk chip & export.
  static const Map<String, String> _statusLabel = {
    'BELUM': 'Belum Mulai',
    'P30': '30%',
    'P50': '50%',
    'P70': '70%',
    'P90': '90%',
    'SELESAI': 'Selesai',
  };

  static Color _statusColor(String code) {
    switch (code) {
      case 'SELESAI':
        return const Color(0xFF1D8F5A);
      case 'P90':
        return const Color(0xFF2E9E6B);
      case 'P70':
        return const Color(0xFF2D77D0);
      case 'P50':
        return const Color(0xFFE08A00);
      case 'P30':
        return const Color(0xFFE05A2B);
      case 'BELUM':
        return const Color(0xFFB0392B);
      default:
        return const Color(0xFF8895A7);
    }
  }

  /// Muat seluruh status pendataan manual (semua wilayah).
  Future<void> _loadStatusPendataan() async {
    final records = await _rekapService.fetchStatusPendataan();
    final byStatus = <String, String>{};
    final byNote = <String, String>{};
    for (final r in records) {
      if (r.kodeWilayah.isEmpty || r.status.isEmpty) continue;
      byStatus[r.kodeWilayah] = r.status;
      if (r.note != null && r.note!.isNotEmpty) {
        byNote[r.kodeWilayah] = r.note!;
      }
    }
    _statusByWilayah = byStatus;
    _noteByWilayah = byNote;
    _statusLoaded = true;
  }

  /// Muat seluruh baris wilayah dalam scope (untuk rekap status di level
  /// petugas). Berat untuk admin (satu RPC per petugas) → hanya on-demand,
  /// lalu di-cache sampai refresh.
  Future<void> _loadAllWilayah() async {
    if (_allWilayahLoading) return;
    final profile = _profile;
    if (profile == null) return;
    setState(() => _allWilayahLoading = true);
    try {
      final groups = await _collectPetugasWilayahGroups(profile);
      if (!mounted) return;
      setState(() {
        _allWilayahGroups = groups;
        _allWilayahLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _allWilayahLoading = false);
    }
  }

  /// Kumpulkan wilayah (SLS/sub-SLS) semua petugas dalam scope, dikelompokkan
  /// per petugas beserta identitasnya.
  Future<List<_PetugasWilayahGroup>> _collectPetugasWilayahGroups(
    Se2026UserProfile profile,
  ) async {
    if (profile.role == 'pendata') {
      final payload = await _rekapService.fetchRekap(limit: 500);
      return [
        _PetugasWilayahGroup(name: '(Saya)', email: '', wilayah: payload.rows),
      ];
    }

    final petugasPayload = profile.role == 'admin'
        ? await _rekapService.fetchRekap(
            allPetugas: true,
            limit: 500,
            sortBy: 'title',
          )
        : await _rekapService.fetchRekap(limit: 500, sortBy: 'title');

    final groups = <_PetugasWilayahGroup>[];
    for (final petugas in petugasPayload.rows) {
      if (petugas.unitId.trim().isEmpty) continue;
      final wilayahPayload = await _rekapService.fetchRekap(
        petugasId: petugas.unitId,
        limit: 500,
      );
      if (wilayahPayload.rows.isEmpty) continue;
      groups.add(
        _PetugasWilayahGroup(
          name: petugas.title,
          email: petugas.subtitle == '-' ? '' : petugas.subtitle,
          wilayah: wilayahPayload.rows,
        ),
      );
    }
    return groups;
  }

  /// Hitung sebaran status untuk sekumpulan wilayah: jumlah per kode status
  /// plus [belum] (wilayah tanpa status).
  (Map<String, int>, int) _statusCountsOf(List<FasihRekapRow> wilayah) {
    final counts = {for (final c in _statusOrder) c: 0};
    var belum = 0;
    for (final row in wilayah) {
      final code = _statusOf(row);
      if (code != null && counts.containsKey(code)) {
        counts[code] = counts[code]! + 1;
      } else {
        belum++;
      }
    }
    return (counts, belum);
  }

  /// Kode status untuk satu wilayah, atau null bila belum ditandai.
  String? _statusOf(FasihRekapRow row) => _statusByWilayah[row.unitId];

  /// Label status siap tampil (mis. untuk export); '' bila belum ditandai.
  String _statusLabelOf(FasihRekapRow row) {
    final code = _statusByWilayah[row.unitId];
    if (code == null) return '';
    return _statusLabel[code] ?? code;
  }

  /// Buka editor pemilihan status untuk sebuah wilayah lalu simpan ke server.
  Future<void> _editStatus(FasihRekapRow row) async {
    final current = _statusByWilayah[row.unitId];
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text(
                  'Status Pendataan',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  row.title,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ),
              const Divider(height: 1),
              for (final code in _statusOrder)
                ListTile(
                  leading: Icon(
                    current == code
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: _statusColor(code),
                  ),
                  title: Text(_statusLabel[code] ?? code),
                  onTap: () => Navigator.of(sheetContext).pop(code),
                ),
              if (current != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red[400],
                  ),
                  title: Text(
                    'Hapus status',
                    style: TextStyle(color: Colors.red[400]),
                  ),
                  onTap: () => Navigator.of(sheetContext).pop('__DELETE__'),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected == null || _savingStatus) return;
    if (selected == current) return;
    if (!mounted) return;

    setState(() => _savingStatus = true);
    final messenger = ScaffoldMessenger.of(context);
    String? error;
    if (selected == '__DELETE__') {
      error = await _rekapService.deleteStatusPendataan(row.unitId);
      if (error == null) {
        _statusByWilayah.remove(row.unitId);
        _noteByWilayah.remove(row.unitId);
      }
    } else {
      error = await _rekapService.upsertStatusPendataan(
        kodeWilayah: row.unitId,
        status: selected,
      );
      if (error == null) _statusByWilayah[row.unitId] = selected;
    }
    if (!mounted) return;
    setState(() => _savingStatus = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(error ?? 'Status pendataan tersimpan.'),
        backgroundColor: error == null ? null : Colors.red,
      ),
    );
  }

  /// Chip status untuk sel tabel wilayah (ketuk untuk mengubah).
  Widget _statusChip(FasihRekapRow row) {
    final code = _statusOf(row);
    final color = code == null ? const Color(0xFF8895A7) : _statusColor(code);
    final label = code == null ? 'Tandai' : (_statusLabel[code] ?? code);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _savingStatus ? null : () => _editStatus(row),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: code == null ? 0.06 : 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withValues(alpha: code == null ? 0.4 : 0.7),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                code == null ? Icons.add_rounded : Icons.circle,
                size: code == null ? 15 : 9,
                color: color,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: code == null ? Colors.blueGrey[500] : color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Target prelist untuk satu baris tabel sesuai level yang sedang tampil.
  int _targetOf(FasihRekapRow row) {
    return _isPetugasLevel
        ? (_prelistByPetugas[row.unitId] ?? 0)
        : (_prelistByWilayah[row.unitId] ?? 0);
  }

  /// Total target seluruh baris yang sedang tampil.
  int get _summaryTarget =>
      _payload.rows.fold(0, (sum, row) => sum + _targetOf(row));

  /// Kategori sebaran bertingkat (dievaluasi berurutan, ambil yang pertama
  /// terpenuhi). "Potensi" = submitted + draft.
  static const List<_Tier> _tiers = [
    _Tier(label: '> 300', sub: 'Submitted', color: Color(0xFF1B7A43)),
    _Tier(label: '> 270', sub: 'Submitted', color: Color(0xFF1D8F5A)),
    _Tier(
      label: '> 270 Potensi',
      sub: 'Submitted + Draft',
      color: Color(0xFF2D77D0),
    ),
    _Tier(
      label: '> 250 Potensi',
      sub: 'Submitted + Draft',
      color: Color(0xFFF59E0B),
    ),
    _Tier(label: 'Lainnya', sub: 'Di bawah ambang', color: Color(0xFF8895A7)),
  ];

  /// Tentukan indeks tier untuk satu baris.
  int _tierIndexOf(FasihRekapRow row) {
    final breakdown = _breakdownOf(
      row.statusCounts,
      row.totalAssignment,
      row.totalTerkirim,
    );
    final submitted = breakdown.submitted;
    final potensi = submitted + breakdown.draft;
    if (submitted > 300) return 0;
    if (submitted > 270) return 1;
    if (potensi > 270) return 2;
    if (potensi > 250) return 3;
    return 4;
  }

  /// Hitung jumlah baris per tier untuk baris yang sedang tampil.
  List<int> get _tierCounts {
    final counts = List<int>.filled(_tiers.length, 0);
    for (final row in _payload.rows) {
      counts[_tierIndexOf(row)]++;
    }
    return counts;
  }

  /// Baris yang ditampilkan tabel, sudah menerapkan filter kategori (bila ada).
  List<FasihRekapRow> get _filteredRows {
    if (_selectedTier == null) return _payload.rows;
    return _payload.rows
        .where((row) => _tierIndexOf(row) == _selectedTier)
        .toList();
  }

  void _toggleTierFilter(int index) {
    setState(() {
      _selectedTier = _selectedTier == index ? null : index;
      _resetSort();
    });
  }

  void _openPetugas(FasihRekapRow petugas) {
    setState(() {
      _selectedPetugas = petugas;
      _searchController.clear();
      _resetSort();
      _selectedTier = null;
      // Tab Pengawas hanya ada di level atas.
      if (_tableTab == 3) _tableTab = 0;
    });
    _loadData();
  }

  void _backToPetugasList() {
    setState(() {
      _selectedPetugas = null;
      _searchController.clear();
      _resetSort();
      _selectedTier = null;
    });
    _loadData();
  }

  void _resetSort() {
    _sortColumnIndex = null;
    _sortAscending = true;
    _statusPetugasSortCol = null;
    _statusPetugasAsc = true;
    _statusSlsSortCol = null;
    _statusSlsAsc = true;
    _statusFilter = null;
  }

  void _onStatusSlsSort(int columnIndex, bool ascending) {
    setState(() {
      _statusSlsSortCol = columnIndex;
      _statusSlsAsc = ascending;
    });
  }

  void _onStatusPetugasSort(int columnIndex, bool ascending) {
    setState(() {
      _statusPetugasSortCol = columnIndex;
      _statusPetugasAsc = ascending;
    });
  }

  void _toggleStatusFilter(String code) {
    setState(() => _statusFilter = _statusFilter == code ? null : code);
  }

  /// Cocokkan satu wilayah dengan filter status aktif.
  bool _statusRowMatchesFilter(FasihRekapRow row) {
    if (_statusFilter == null) return true;
    final code = _statusOf(row);
    if (_statusFilter == _belumTandaKey) return code == null;
    return code == _statusFilter;
  }

  /// Peringkat status untuk pengurutan (mengikuti _statusOrder; belum ditandai
  /// diletakkan paling akhir).
  int _statusRank(FasihRekapRow row) {
    final code = _statusOf(row);
    final idx = code == null ? -1 : _statusOrder.indexOf(code);
    return idx < 0 ? _statusOrder.length : idx;
  }

  /// Nilai sortir tabel rincian per SLS/sub-SLS (tab Status).
  Comparable<dynamic> _statusSlsSortValue(FasihRekapRow row, int index) {
    final b = _breakdownOf(
      row.statusCounts,
      row.totalAssignment,
      row.totalTerkirim,
    );
    final target = _targetOf(row);
    switch (index) {
      case 2:
        return row.unitId.length >= 16 ? row.unitId.substring(14, 16) : '';
      case 3:
        return row.title.toLowerCase();
      case 4:
        return _statusRank(row);
      case 5:
        return target;
      case 6:
        return b.submitted;
      case 7:
        return target > 0 ? b.submitted / target : -1.0;
      default:
        return row.unitId; // kolom SLS: unitId penuh agar sub berkelompok.
    }
  }

  /// Nilai sortir tabel rekap per petugas (tab Status).
  Comparable<dynamic> _statusPetugasSortValue(
    _PetugasWilayahGroup group,
    int index,
  ) {
    if (index == 1) return group.name.toLowerCase();
    final (counts, belum) = _statusCountsOf(group.wilayah);
    final statusCount = _statusOrder.length; // 6
    if (index >= 2 && index < 2 + statusCount) {
      return counts[_statusOrder[index - 2]] ?? 0;
    }
    if (index == 2 + statusCount) return belum; // kolom "Belum"
    return group.wilayah.length; // kolom "Total"
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  // ---------------------------------------------------------------------
  // Export Excel: SEMUA wilayah (SLS/sub-SLS) untuk seluruh petugas dalam
  // scope pengguna, apa pun level yang sedang tampil.
  // ---------------------------------------------------------------------

  Future<void> _exportAllWilayah() async {
    if (_isExporting) return;
    final profile = _profile;
    if (profile == null) return;

    setState(() => _isExporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final rows = await _collectAllWilayahRows(profile);
      if (rows.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Tidak ada wilayah untuk diekspor.')),
        );
        return;
      }
      final path = await _exportService.exportToFile(rows);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Berhasil mengekspor ${rows.length} wilayah.')),
      );
      await OpenFile.open(path);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal mengekspor: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Kumpulkan seluruh baris wilayah untuk semua petugas dalam scope pengguna.
  Future<List<LembarKerjaExportRow>> _collectAllWilayahRows(
    Se2026UserProfile profile,
  ) async {
    // Pastikan target prelist tersedia untuk kolom Target.
    if (!_prelistLoaded) {
      await _loadPrelistTargets(profile);
    }
    // Pastikan progres riil tersedia untuk kolom Keluarga/Usaha/Total/Tidak
    // Ditemukan.
    if (!_riilLoaded && !_riilLoading) {
      await _loadRiil();
    }
    // Sedang dimuat oleh halaman (initState) → tunggu sampai selesai.
    while (_riilLoading && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // Distribusi kode_bang per wilayah (untuk kolom-kolom jenis bangunan di
    // Excel) diambil langsung dari RPC saat ekspor.
    final kodeBangByWilayah = <String, Map<String, int>>{};
    for (final r in await _rekapService.fetchKodeBangByWilayah()) {
      if (r.kodeWilayah.isEmpty || r.counts.isEmpty) continue;
      final m = kodeBangByWilayah.putIfAbsent(
        r.kodeWilayah,
        () => <String, int>{},
      );
      r.counts.forEach((c, n) => m[c] = (m[c] ?? 0) + n);
    }

    // Pendata: cukup wilayah tugasnya sendiri.
    if (profile.role == 'pendata') {
      final payload = await _rekapService.fetchRekap(limit: 500);
      return payload.rows
          .map(
            (row) => _toExportRow(
              row,
              petugas: '(Saya)',
              email: '',
              kodeBangByWilayah: kodeBangByWilayah,
            ),
          )
          .toList();
    }

    // Admin & pengawas: ambil daftar petugas, lalu wilayah tiap petugas.
    final petugasPayload = profile.role == 'admin'
        ? await _rekapService.fetchRekap(
            allPetugas: true,
            limit: 500,
            sortBy: 'title',
          )
        : await _rekapService.fetchRekap(limit: 500, sortBy: 'title');

    final result = <LembarKerjaExportRow>[];
    for (final petugas in petugasPayload.rows) {
      // Lewati baris "tanpa petugas" (ppl_id null → unitId kosong); tidak bisa
      // di-drill per petugas dan string kosong tak valid sebagai UUID.
      if (petugas.unitId.trim().isEmpty) continue;
      final wilayahPayload = await _rekapService.fetchRekap(
        petugasId: petugas.unitId,
        limit: 500,
      );
      for (final row in wilayahPayload.rows) {
        result.add(
          _toExportRow(
            row,
            petugas: petugas.title,
            email: petugas.subtitle == '-' ? '' : petugas.subtitle,
            kodeBangByWilayah: kodeBangByWilayah,
          ),
        );
      }
    }
    return result;
  }

  LembarKerjaExportRow _toExportRow(
    FasihRekapRow row, {
    required String petugas,
    required String email,
    required Map<String, Map<String, int>> kodeBangByWilayah,
  }) {
    final breakdown = _breakdownOf(
      row.statusCounts,
      row.totalAssignment,
      row.totalTerkirim,
    );
    // Ekspor selalu level wilayah → pakai agregat riil per wilayah.
    final riil = _riilByWilayah[row.unitId] ?? _Riil();
    return LembarKerjaExportRow(
      petugas: petugas,
      petugasEmail: email,
      kodeWilayah: row.unitId,
      namaSls: row.title,
      kecDesa: row.subtitle == '-' ? '' : row.subtitle,
      target: _prelistByWilayah[row.unitId] ?? 0,
      total: row.totalAssignment,
      submitted: breakdown.submitted,
      draft: breakdown.draft,
      open: breakdown.open,
      keluarga: riil.kkRiil,
      usaha: riil.usahaRiil,
      tidakDitemukan: riil.tidakDitemukan,
      status: _statusLabelOf(row),
      kodeBang: kodeBangByWilayah[row.unitId] ?? const {},
    );
  }

  // ---------------------------------------------------------------------
  // Hitungan status: submitted = semua status selain DRAFT dan OPEN.
  // ---------------------------------------------------------------------

  static bool _isOpenStatus(String status) =>
      status.trim().toUpperCase().startsWith('OPEN');

  static bool _isDraftStatus(String status) =>
      status.trim().toUpperCase().startsWith('DRAFT');

  /// Hitung open/draft/submitted dari rincian status sebuah unit.
  /// [totalAssignment] dan [totalTerkirim] dipakai sebagai fallback jika
  /// rincian status kosong.
  static _StatusBreakdown _breakdownOf(
    Map<String, int> statusCounts,
    int totalAssignment,
    int totalTerkirim,
  ) {
    if (statusCounts.isEmpty) {
      return _StatusBreakdown(
        open: totalAssignment - totalTerkirim,
        draft: 0,
        submitted: totalTerkirim,
      );
    }
    int open = 0;
    int draft = 0;
    int submitted = 0;
    statusCounts.forEach((status, count) {
      if (_isOpenStatus(status)) {
        open += count;
      } else if (_isDraftStatus(status)) {
        draft += count;
      } else {
        submitted += count;
      }
    });
    return _StatusBreakdown(open: open, draft: draft, submitted: submitted);
  }

  /// Breakdown gabungan seluruh payload (dipakai kartu ringkasan).
  _StatusBreakdown get _summaryBreakdown {
    final counts = <String, int>{};
    for (final alias in _payload.statusAliases) {
      counts[alias.alias] = (counts[alias.alias] ?? 0) + alias.total;
    }
    return _breakdownOf(
      counts,
      _payload.summary.totalAssignments,
      _payload.summary.totalTerkirim,
    );
  }

  String get _pageTitle {
    if (_role == 'pendata') return 'Lembar Kerja Saya';
    return _selectedPetugas == null
        ? 'Lembar Kerja Petugas'
        : 'Lembar Kerja: ${_selectedPetugas!.title}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedPetugas == null || _role == 'pendata',
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedPetugas != null && _role != 'pendata') {
          _backToPetugasList();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F6FB),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F4C81),
          foregroundColor: Colors.white,
          title: Text(_pageTitle, overflow: TextOverflow.ellipsis),
          leading: _selectedPetugas != null && _role != 'pendata'
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _backToPetugasList,
                )
              : null,
          actions: [
            IconButton(
              tooltip: 'Export Excel (semua wilayah)',
              onPressed: _isExporting || _isLoading ? null : _exportAllWilayah,
              icon: _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.file_download_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _refreshAll,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    children: [
                      _buildSummaryCard(),
                      const SizedBox(height: 12),
                      _buildDistributionCard(),
                      const SizedBox(height: 12),
                      _buildSearchField(),
                      const SizedBox(height: 12),
                      _buildTableCard(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Terjadi kesalahan.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[700]),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final summary = _payload.summary;
    final breakdown = _summaryBreakdown;
    final target = _summaryTarget;
    // Capaian dibandingkan terhadap target prelist; jika target belum diisi,
    // pakai total assignment sebagai pembanding.
    final percent = target > 0
        ? breakdown.submitted / target
        : (summary.totalAssignments == 0
              ? 0.0
              : breakdown.submitted / summary.totalAssignments);
    final unitLabel = _isPetugasLevel ? 'Petugas' : 'SLS/Sub-SLS';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F4C81), Color(0xFF2D77D0), Color(0xFF7AB6FF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D77D0).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.assignment_turned_in_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedPetugas?.title ??
                          (_role == 'pendata'
                              ? 'Progres Wilayah Tugas Anda'
                              : 'Progres Per Petugas'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      target > 0
                          ? '${summary.totalUnits} $unitLabel • '
                                '${breakdown.submitted} submitted dari target $target'
                          : '${summary.totalUnits} $unitLabel • '
                                '${breakdown.submitted}/${summary.totalAssignments} submitted',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(percent * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percent.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF7CFFB2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildSummaryStat('Target', target)),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSummaryStat('Submitted', breakdown.submitted),
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildSummaryStat('Draft', breakdown.draft)),
              const SizedBox(width: 8),
              Expanded(child: _buildSummaryStat('Open', breakdown.open)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStat(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionCard() {
    final counts = _tierCounts;
    final unitLabel = _isPetugasLevel ? 'petugas' : 'SLS/sub-SLS';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sebaran Capaian $unitLabel',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            _selectedTier == null
                ? 'Ketuk kategori untuk memfilter tabel.'
                : 'Filter aktif: ${_tiers[_selectedTier!].label}. '
                      'Ketuk lagi untuk hapus.',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < _tiers.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: _buildTierTile(i, _tiers[i], counts[i])),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierTile(int index, _Tier tier, int value) {
    final selected = _selectedTier == index;
    return Material(
      color: selected
          ? tier.color.withValues(alpha: 0.18)
          : tier.color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggleTierFilter(index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: tier.color.withValues(alpha: selected ? 0.9 : 0.22),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                '$value',
                style: TextStyle(
                  color: tier.color,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tier.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: tier.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _loadData(),
      decoration: InputDecoration(
        hintText: _isPetugasLevel
            ? 'Cari nama petugas...'
            : 'Cari nama SLS / desa / kecamatan...',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _searchController.clear();
                  _loadData();
                },
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Tabel
  // ---------------------------------------------------------------------

  Widget _buildTableCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _tableTab == 3
                      ? 'Tabel Per Pengawas'
                      : _isPetugasLevel
                      ? 'Tabel Per Petugas'
                      : 'Tabel Per SLS/Sub-SLS',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _payload.rows.isEmpty ? null : _copyCurrentTable,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Salin'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0F4C81),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _tableSubtitle(),
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 12),
          _buildTableTabs(),
          const SizedBox(height: 12),
          if (_tableTab == 3)
            _buildPengawasTable()
          else if (_payload.rows.isEmpty)
            _buildEmptyState(
              _isPetugasLevel
                  ? 'Belum ada data petugas.'
                  : 'Belum ada wilayah tugas untuk ditampilkan.',
            )
          else if (_filteredRows.isEmpty)
            _buildEmptyState('Tidak ada baris pada kategori ini.')
          else if (_tableTab == 4)
            _buildStatusRekap()
          else
            _buildProgresTable(),
        ],
      ),
    );
  }

  /// Baris yang ditampilkan tabel aktif: terfilter + terurut sesuai sort.
  List<FasihRekapRow> _displayRows() {
    final rows = [..._filteredRows];
    if (_sortColumnIndex != null) {
      _sortRows(rows, (r) => _progresSortValue(r, _sortColumnIndex!));
    } else if (!_isPetugasLevel) {
      rows.sort((a, b) => a.unitId.compareTo(b.unitId));
    }
    return rows;
  }

  /// Salin tabel yang sedang tampil ke clipboard sebagai TSV (siap tempel ke
  /// Excel/Sheets), mengikuti tab, level, filter, dan sort aktif.
  Future<void> _copyCurrentTable() async {
    final messenger = ScaffoldMessenger.of(context);
    final lines = <List<String>>[];

    String pct(int submitted, int target) =>
        target > 0 ? '${(submitted / target * 100).toStringAsFixed(2)}%' : '';

    // Tab Pengawas punya sumber baris sendiri.
    if (_tableTab == 3) {
      final pengawasRows = (_pengawasPayload?.rows ?? const <FasihRekapRow>[])
          .where((row) => row.unitId.trim().isNotEmpty)
          .toList();
      if (_sortColumnIndex != null) {
        _sortRows(
          pengawasRows,
          (row) => _pengawasSortValue(row, _sortColumnIndex!),
        );
      }
      lines.add([
        'No',
        'Pengawas',
        'Email',
        'Target',
        'Total',
        'Submitted',
        'Draft',
        'Open',
        'Approved',
        'Approved+',
        '%',
      ]);
      for (var i = 0; i < pengawasRows.length; i++) {
        final row = pengawasRows[i];
        final b = _breakdownOf(
          row.statusCounts,
          row.totalAssignment,
          row.totalTerkirim,
        );
        final target = _prelistByPengawas[row.unitId] ?? 0;
        final approved = _approvedOf(row.statusCounts);
        final approvedPlus = _approvedPlusOf(row.statusCounts);
        lines.add([
          '${i + 1}',
          row.title,
          row.subtitle == '-' ? '' : row.subtitle,
          '$target',
          '${row.totalAssignment}',
          '${b.submitted}',
          '${b.draft}',
          '${b.open}',
          '$approved',
          '$approvedPlus',
          pct(approvedPlus, target),
        ]);
      }
      final text = lines.map((r) => r.join('\t')).join('\n');
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Tersalin ${pengawasRows.length} baris ke clipboard.'),
        ),
      );
      return;
    }

    final rows = _displayRows();
    List<String> identityHeaders() =>
        _isPetugasLevel ? ['Petugas'] : ['SLS', 'Sub', 'Nama SLS'];
    List<String> identityValues(FasihRekapRow row) {
      if (_isPetugasLevel) return [row.title];
      final kodeSls = row.unitId.length >= 14
          ? row.unitId.substring(10, 14)
          : row.unitId;
      final kodeSubsls = row.unitId.length >= 16
          ? row.unitId.substring(14, 16)
          : '-';
      return [kodeSls, kodeSubsls, row.title];
    }

    if (_tableTab == 4 && _isPetugasLevel) {
      // Rekap status per petugas.
      final groups = [...(_allWilayahGroups ?? const <_PetugasWilayahGroup>[])]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      lines.add([
        'No',
        'Petugas',
        'Email',
        for (final c in _statusOrder) _statusLabel[c] ?? c,
        'Belum',
        'Total',
      ]);
      for (var i = 0; i < groups.length; i++) {
        final g = groups[i];
        final (counts, belum) = _statusCountsOf(g.wilayah);
        lines.add([
          '${i + 1}',
          g.name,
          g.email,
          for (final c in _statusOrder) '${counts[c] ?? 0}',
          '$belum',
          '${g.wilayah.length}',
        ]);
      }
    } else if (_tableTab == 4) {
      // Rincian status per SLS/sub-SLS (level wilayah), menghormati filter.
      final statusRows = rows.where(_statusRowMatchesFilter).toList()
        ..sort((a, b) => a.unitId.compareTo(b.unitId));
      lines.add([
        'No',
        'SLS',
        'Sub',
        'Nama SLS',
        'Status',
        'Target',
        'Submitted',
        '%',
      ]);
      for (var i = 0; i < statusRows.length; i++) {
        final row = statusRows[i];
        final b = _breakdownOf(
          row.statusCounts,
          row.totalAssignment,
          row.totalTerkirim,
        );
        final target = _targetOf(row);
        final kodeSls = row.unitId.length >= 14
            ? row.unitId.substring(10, 14)
            : row.unitId;
        final kodeSubsls = row.unitId.length >= 16
            ? row.unitId.substring(14, 16)
            : '-';
        lines.add([
          '${i + 1}',
          kodeSls,
          kodeSubsls,
          row.title,
          _statusLabelOf(row),
          '$target',
          '${b.submitted}',
          pct(b.submitted, target),
        ]);
      }
    } else {
      // Progres (gabungan).
      lines.add([
        'No',
        ...identityHeaders(),
        'Target',
        'Submitted',
        'Draft',
        'Open',
        'Keluarga',
        'Usaha',
        'Total',
        'Tidak Ditemukan',
        '%',
      ]);
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final b = _breakdownOf(
          row.statusCounts,
          row.totalAssignment,
          row.totalTerkirim,
        );
        final r = _riilForRow(row);
        final target = _targetOf(row);
        final total = r.kkRiil + r.usahaRiil;
        lines.add([
          '${i + 1}',
          ...identityValues(row),
          '$target',
          '${b.submitted}',
          '${b.draft}',
          '${b.open}',
          '${r.kkRiil}',
          '${r.usahaRiil}',
          '$total',
          '${r.tidakDitemukan}',
          pct(total, target),
        ]);
      }
    }
    final text = lines.map((r) => r.join('\t')).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Tersalin ${lines.length - 1} baris ke clipboard.'),
      ),
    );
  }

  String _tableSubtitle() {
    switch (_tableTab) {
      case 3:
        return 'Approved = disetujui pengawas. Approved+ = semua status selain '
            'OPEN, DRAFT & SUBMITTED BY PENCACAH. % = Approved+/target; '
            'baris hijau = capaian 40% ke atas.';
      case 4:
        return _isPetugasLevel
            ? 'Rekap status seluruh SLS/sub-SLS dalam cakupan Anda. Ketuk chip '
                  'status untuk mengubah. % = submitted otomatis / target.'
            : 'Status pendataan manual per SLS/sub-SLS. Ketuk chip status '
                  'untuk mengubah. % = submitted otomatis dibanding target.';
      default:
        return _isPetugasLevel
            ? 'Submitted/Draft/Open + hasil riil (Keluarga, Usaha, Total, '
                  'Tidak Ditemukan). Total = Keluarga + Usaha, % = Total/target. '
                  'Ketuk baris petugas untuk rincian per SLS.'
            : 'Submitted/Draft/Open + hasil riil per SLS/sub-SLS. '
                  'Total = Keluarga + Usaha, % = Total/target. '
                  'Ketuk baris SLS untuk membukanya di peta (Jelajah).';
    }
  }

  Widget _buildTableTabs() {
    Widget seg(int idx, IconData icon, String label) {
      final active = _tableTab == idx;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (_tableTab == idx) return;
            setState(() {
              _tableTab = idx;
              _resetSort();
            });
            if (idx == 3 && _pengawasPayload == null) {
              _loadPengawas();
            }
            if (idx == 4 && _isPetugasLevel && _allWilayahGroups == null) {
              _loadAllWilayah();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF0F4C81) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: active ? Colors.white : Colors.blueGrey,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? Colors.white : Colors.blueGrey[700],
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          seg(0, Icons.insights_rounded, 'Progres'),
          const SizedBox(width: 4),
          seg(4, Icons.checklist_rounded, 'Status'),
          if (_role == 'admin' && _isPetugasLevel) ...[
            const SizedBox(width: 4),
            seg(3, Icons.supervisor_account_rounded, 'Pengawas'),
          ],
        ],
      ),
    );
  }

  DataCell _totalLabelCell(String label) {
    return DataCell(
      Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }

  /// Nilai sortir kolom tabel pengawas (indeks sesuai urutan header).
  Comparable<dynamic> _pengawasSortValue(FasihRekapRow row, int index) {
    final breakdown = _breakdownOf(
      row.statusCounts,
      row.totalAssignment,
      row.totalTerkirim,
    );
    final target = _prelistByPengawas[row.unitId] ?? 0;
    final approved = _approvedOf(row.statusCounts);
    switch (index) {
      case 2:
        return target;
      case 3:
        return row.totalAssignment;
      case 4:
        return breakdown.submitted;
      case 5:
        return breakdown.draft;
      case 6:
        return breakdown.open;
      case 7:
        return approved;
      case 8:
        return _approvedPlusOf(row.statusCounts);
      case 9:
        final approvedPlus = _approvedPlusOf(row.statusCounts);
        return target > 0 ? approvedPlus / target : -1.0;
      default:
        return row.title.toLowerCase();
    }
  }

  /// Tabel tab "Pengawas": progres per pengawas + kolom Approved dan
  /// persentase Approved terhadap target prelist binaannya.
  Widget _buildPengawasTable() {
    if (_pengawasLoading || _pengawasPayload == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final payload = _pengawasPayload!;
    if (payload.rows.isEmpty) {
      return _buildEmptyState('Belum ada data pengawas.');
    }

    final rows = payload.rows
        .where((row) => row.unitId.trim().isNotEmpty)
        .toList();
    if (_sortColumnIndex != null) {
      _sortRows(rows, (row) => _pengawasSortValue(row, _sortColumnIndex!));
    }

    // Baris total.
    var totTarget = 0;
    var totAssignment = 0;
    var totSubmitted = 0;
    var totDraft = 0;
    var totOpen = 0;
    var totApproved = 0;
    var totApprovedPlus = 0;
    for (final row in rows) {
      final b = _breakdownOf(
        row.statusCounts,
        row.totalAssignment,
        row.totalTerkirim,
      );
      totTarget += _prelistByPengawas[row.unitId] ?? 0;
      totAssignment += row.totalAssignment;
      totSubmitted += b.submitted;
      totDraft += b.draft;
      totOpen += b.open;
      totApproved += _approvedOf(row.statusCounts);
      totApprovedPlus += _approvedPlusOf(row.statusCounts);
    }

    return _fullWidthScroll(
      DataTable(
        showCheckboxColumn: false,
        horizontalMargin: 12,
        columnSpacing: 18,
        headingRowHeight: 48,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 60,
        sortColumnIndex: _sortColumnIndex,
        sortAscending: _sortAscending,
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
        columns: [
          _noColumn(),
          DataColumn(onSort: _onSort, label: const Text('Pengawas')),
          _numColumn('Target'),
          _numColumn('Total'),
          _numColumn('Submitted'),
          _numColumn('Draft'),
          _numColumn('Open'),
          _numColumn('Approved'),
          _numColumn('Approved+'),
          _numColumn('%'),
        ],
        rows:
            rows.asMap().entries.map((entry) {
              final row = entry.value;
              final b = _breakdownOf(
                row.statusCounts,
                row.totalAssignment,
                row.totalTerkirim,
              );
              final target = _prelistByPengawas[row.unitId] ?? 0;
              final approved = _approvedOf(row.statusCounts);
              final approvedPlus = _approvedPlusOf(row.statusCounts);
              final hijau = target > 0 && approvedPlus / target >= 0.4;
              return DataRow(
                color: hijau
                    ? WidgetStateProperty.all(const Color(0xFFE3F4EA))
                    : null,
                cells: [
                  _noCell(entry.key + 1),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 190),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (row.subtitle.isNotEmpty && row.subtitle != '-')
                            Text(
                              row.subtitle,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blueGrey[400],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  _numCell(target, color: const Color(0xFF0F4C81)),
                  _numCell(row.totalAssignment),
                  _numCell(b.submitted, color: const Color(0xFF1D8F5A)),
                  _numCell(b.draft, color: Colors.orange[800]),
                  _numCell(b.open, color: Colors.blueGrey[500]),
                  _numCell(approved, color: const Color(0xFF6B4FBB)),
                  _numCell(approvedPlus, color: const Color(0xFF0F766E)),
                  _percentCell(approvedPlus, target),
                ],
              );
            }).toList()..add(
              DataRow(
                color: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
                cells: [
                  const DataCell(Text('')),
                  _totalLabelCell('Total (${rows.length} pengawas)'),
                  _numCell(totTarget, color: const Color(0xFF0F4C81)),
                  _numCell(totAssignment),
                  _numCell(totSubmitted, color: const Color(0xFF1D8F5A)),
                  _numCell(totDraft, color: Colors.orange[800]),
                  _numCell(totOpen, color: Colors.blueGrey[500]),
                  _numCell(totApproved, color: const Color(0xFF6B4FBB)),
                  _numCell(totApprovedPlus, color: const Color(0xFF0F766E)),
                  _percentCell(totApprovedPlus, totTarget),
                ],
              ),
            ),
      ),
    );
  }

  /// Jumlah kolom identitas (setelah kolom No) untuk tab Bangunan/Rekap.
  int get _idCount => _isPetugasLevel ? 1 : 3;

  /// Kolom identitas (sortable) untuk tab Bangunan/Rekap.
  List<DataColumn> _identityColumns() {
    if (_isPetugasLevel) {
      return [DataColumn(onSort: _onSort, label: const Text('Petugas'))];
    }
    return [
      DataColumn(onSort: _onSort, label: const Text('SLS')),
      DataColumn(onSort: _onSort, label: const Text('Sub')),
      DataColumn(onSort: _onSort, label: const Text('Nama SLS')),
    ];
  }

  /// Nilai sortir kolom identitas (indeks 1..idCount).
  Comparable<dynamic> _identitySortValue(FasihRekapRow row, int index) {
    if (_isPetugasLevel) return row.title.toLowerCase();
    switch (index) {
      case 1:
        return row.unitId; // SLS: unitId penuh agar sub tetap berkelompok.
      case 2:
        return row.unitId.length >= 16 ? row.unitId.substring(14, 16) : '';
      default:
        return row.title.toLowerCase(); // Nama SLS.
    }
  }

  /// Sel identitas untuk tabel per baris sesuai level.
  List<DataCell> _kodeBangIdentityCells(FasihRekapRow row) {
    if (_isPetugasLevel) {
      return [
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              row.title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ];
    }
    final kodeSls = row.unitId.length >= 14
        ? row.unitId.substring(10, 14)
        : row.unitId;
    final kodeSubsls = row.unitId.length >= 16
        ? row.unitId.substring(14, 16)
        : '-';
    return [
      DataCell(
        Text(
          kodeSls,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F4C81),
          ),
        ),
      ),
      DataCell(Text(kodeSubsls)),
      DataCell(
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 190),
          child: Text(
            row.title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ];
  }

  /// Nilai sortir tab Progres (gabungan): identitas, Target, Submitted, Draft,
  /// Open, Keluarga, Usaha, Total, Tidak Ditemukan, lalu %.
  Comparable<dynamic> _progresSortValue(FasihRekapRow row, int index) {
    final idc = _idCount;
    if (index <= idc) return _identitySortValue(row, index);
    final b = _breakdownOf(
      row.statusCounts,
      row.totalAssignment,
      row.totalTerkirim,
    );
    final r = _riilForRow(row);
    final target = _targetOf(row);
    switch (index - idc - 1) {
      case 0:
        return target;
      case 1:
        return b.submitted;
      case 2:
        return b.draft;
      case 3:
        return b.open;
      case 4:
        return r.kkRiil;
      case 5:
        return r.usahaRiil;
      case 6:
        return r.kkRiil + r.usahaRiil; // Total = Keluarga + Usaha.
      case 7:
        return r.tidakDitemukan;
      default: // %
        final total = r.kkRiil + r.usahaRiil;
        return target > 0 ? total / target : -1.0;
    }
  }

  /// Tabel tab "Progres" (gabungan): status pendataan (submitted/draft/open)
  /// + hasil riil (Keluarga/Usaha/Total/Tidak Ditemukan) per baris, dibanding
  /// target prelist. % = Total riil (Keluarga+Usaha) / target.
  Widget _buildProgresTable() {
    if (_riilLoading || !_riilLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final rows = [..._filteredRows];
    if (_sortColumnIndex != null) {
      _sortRows(rows, (r) => _progresSortValue(r, _sortColumnIndex!));
    } else if (!_isPetugasLevel) {
      rows.sort((a, b) => a.unitId.compareTo(b.unitId));
    }

    var totTarget = 0;
    var totSubmitted = 0;
    var totDraft = 0;
    var totOpen = 0;
    var totKk = 0;
    var totUsaha = 0;
    var totTidak = 0;
    for (final row in rows) {
      final b = _breakdownOf(
        row.statusCounts,
        row.totalAssignment,
        row.totalTerkirim,
      );
      final r = _riilForRow(row);
      totTarget += _targetOf(row);
      totSubmitted += b.submitted;
      totDraft += b.draft;
      totOpen += b.open;
      totKk += r.kkRiil;
      totUsaha += r.usahaRiil;
      totTidak += r.tidakDitemukan;
    }
    final totDitemukan = totKk + totUsaha;

    return _fullWidthScroll(
      DataTable(
        showCheckboxColumn: false,
        horizontalMargin: 12,
        columnSpacing: 16,
        headingRowHeight: 48,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 60,
        sortColumnIndex: _sortColumnIndex,
        sortAscending: _sortAscending,
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
        columns: [
          _noColumn(),
          ..._identityColumns(),
          _numColumn('Target'),
          _numColumn('Submitted'),
          _numColumn('Draft'),
          _numColumn('Open'),
          _numColumn('Keluarga'),
          _numColumn('Usaha'),
          _numColumn('Total'),
          _numColumn('Tidak Ditemukan'),
          _numColumn('%'),
        ],
        rows:
            rows.asMap().entries.map((entry) {
              final row = entry.value;
              final b = _breakdownOf(
                row.statusCounts,
                row.totalAssignment,
                row.totalTerkirim,
              );
              final r = _riilForRow(row);
              final target = _targetOf(row);
              final total = r.kkRiil + r.usahaRiil;
              return DataRow(
                onSelectChanged: (_) {
                  if (_isPetugasLevel) {
                    _openPetugas(row);
                  } else {
                    // Level SLS: kembali ke Jelajah & pilih SLS ini di peta.
                    Navigator.of(context).pop(row.unitId);
                  }
                },
                cells: [
                  _noCell(entry.key + 1),
                  ..._kodeBangIdentityCells(row),
                  _numCell(target, color: const Color(0xFF0F4C81)),
                  _numCell(b.submitted, color: const Color(0xFF1D8F5A)),
                  _numCell(b.draft, color: Colors.orange[800]),
                  _numCell(b.open, color: Colors.blueGrey[500]),
                  _numCell(r.kkRiil, color: const Color(0xFF2D77D0)),
                  _numCell(r.usahaRiil, color: const Color(0xFF1D8F5A)),
                  _numCell(total, color: const Color(0xFF0F766E)),
                  _numCell(r.tidakDitemukan, color: Colors.red[400]),
                  _percentCell(total, target),
                ],
              );
            }).toList()..add(
              DataRow(
                color: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
                cells: [
                  const DataCell(Text('')),
                  _totalLabelCell(
                    _isPetugasLevel
                        ? 'Total (${rows.length} petugas)'
                        : 'Total',
                  ),
                  if (!_isPetugasLevel) ...[
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                  ],
                  _numCell(totTarget, color: const Color(0xFF0F4C81)),
                  _numCell(totSubmitted, color: const Color(0xFF1D8F5A)),
                  _numCell(totDraft, color: Colors.orange[800]),
                  _numCell(totOpen, color: Colors.blueGrey[500]),
                  _numCell(totKk, color: const Color(0xFF2D77D0)),
                  _numCell(totUsaha, color: const Color(0xFF1D8F5A)),
                  _numCell(totDitemukan, color: const Color(0xFF0F766E)),
                  _numCell(totTidak, color: Colors.red[400]),
                  _percentCell(totDitemukan, totTarget),
                ],
              ),
            ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tab "Status": ringkasan sebaran status pendataan manual + tabel detail
  // (status berdampingan progres otomatis) per SLS/sub-SLS.
  // -------------------------------------------------------------------------

  Widget _buildStatusRekap() {
    // Di level petugas: rekap dari SELURUH wilayah scope (dimuat on-demand),
    // plus rekap per petugas. Di level wilayah: dari baris yang sedang tampil.
    if (_isPetugasLevel) {
      if (_allWilayahLoading || _allWilayahGroups == null) {
        if (!_allWilayahLoading) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _loadAllWilayah(),
          );
        }
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final groups = _allWilayahGroups!;
      final rows = [..._allWilayahFlat]
        ..sort((a, b) => a.unitId.compareTo(b.unitId));
      final (counts, belum) = _statusCountsOf(rows);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusDistribution(counts, belum, rows.length),
          const SizedBox(height: 16),
          _statusSectionLabel('Rekap per Petugas'),
          const SizedBox(height: 8),
          _buildPetugasStatusTable(groups),
          const SizedBox(height: 16),
          _statusSectionLabel('Rincian per SLS/Sub-SLS'),
          const SizedBox(height: 8),
          _buildStatusDetailTable(rows),
        ],
      );
    }

    final rows = [..._filteredRows]
      ..sort((a, b) => a.unitId.compareTo(b.unitId));
    final (counts, belum) = _statusCountsOf(rows);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatusDistribution(counts, belum, rows.length),
        const SizedBox(height: 14),
        _buildStatusDetailTable(rows),
      ],
    );
  }

  Widget _statusSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Color(0xFF0F4C81),
      ),
    );
  }

  /// Tabel rekap status per petugas: jumlah wilayah tiap kategori status.
  Widget _buildPetugasStatusTable(List<_PetugasWilayahGroup> groups) {
    final sorted = [...groups];
    if (_statusPetugasSortCol != null) {
      sorted.sort((a, b) {
        final cmp = Comparable.compare(
          _statusPetugasSortValue(a, _statusPetugasSortCol!),
          _statusPetugasSortValue(b, _statusPetugasSortCol!),
        );
        return _statusPetugasAsc ? cmp : -cmp;
      });
    } else {
      sorted.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }

    // Total kolom.
    final totCounts = {for (final c in _statusOrder) c: 0};
    var totBelum = 0;
    var totWilayah = 0;

    const headerStyle = TextStyle(fontWeight: FontWeight.w600, fontSize: 12);

    final dataRows = <DataRow>[];
    for (var i = 0; i < sorted.length; i++) {
      final g = sorted[i];
      final (counts, belum) = _statusCountsOf(g.wilayah);
      final total = g.wilayah.length;
      for (final c in _statusOrder) {
        totCounts[c] = totCounts[c]! + (counts[c] ?? 0);
      }
      totBelum += belum;
      totWilayah += total;
      dataRows.add(
        DataRow(
          cells: [
            _noCell(i + 1),
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (g.email.isNotEmpty)
                      Text(
                        g.email,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blueGrey[400],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            for (final c in _statusOrder)
              _numCell(counts[c] ?? 0, color: _statusColor(c)),
            _numCell(belum, color: const Color(0xFF8895A7)),
            _numCell(total, color: const Color(0xFF0F4C81)),
          ],
        ),
      );
    }

    dataRows.add(
      DataRow(
        color: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
        cells: [
          const DataCell(Text('')),
          _totalLabelCell('Total (${sorted.length} petugas)'),
          for (final c in _statusOrder)
            _numCell(totCounts[c] ?? 0, color: _statusColor(c)),
          _numCell(totBelum, color: const Color(0xFF8895A7)),
          _numCell(totWilayah, color: const Color(0xFF0F4C81)),
        ],
      ),
    );

    return _fullWidthScroll(
      DataTable(
        showCheckboxColumn: false,
        horizontalMargin: 12,
        columnSpacing: 16,
        headingRowHeight: 48,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 60,
        sortColumnIndex: _statusPetugasSortCol,
        sortAscending: _statusPetugasAsc,
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
        columns: [
          _noColumn(),
          DataColumn(
            onSort: _onStatusPetugasSort,
            label: const Text('Petugas', style: headerStyle),
          ),
          for (final c in _statusOrder)
            _numColumn(_statusLabel[c] ?? c, onSort: _onStatusPetugasSort),
          _numColumn('Belum', onSort: _onStatusPetugasSort),
          _numColumn('Total', onSort: _onStatusPetugasSort),
        ],
        rows: dataRows,
      ),
    );
  }

  Widget _buildStatusDistribution(
    Map<String, int> counts,
    int belum,
    int total,
  ) {
    Widget tile(String code, String label, int value, Color color) {
      final selected = _statusFilter == code;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _toggleStatusFilter(code),
          child: Container(
            width: 104,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: selected ? 0.2 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withValues(alpha: selected ? 0.95 : 0.3),
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Column(
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EBF6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sebaran Status • $total SLS/sub-SLS',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            _statusFilter == null
                ? 'Ketuk kategori untuk memfilter rincian di bawah.'
                : 'Filter aktif: ${_statusFilterLabel(_statusFilter!)}. '
                      'Ketuk lagi untuk hapus.',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final code in _statusOrder)
                tile(
                  code,
                  _statusLabel[code] ?? code,
                  counts[code] ?? 0,
                  _statusColor(code),
                ),
              tile(
                _belumTandaKey,
                'Belum ditandai',
                belum,
                const Color(0xFF8895A7),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusFilterLabel(String code) =>
      code == _belumTandaKey ? 'Belum ditandai' : (_statusLabel[code] ?? code);

  Widget _buildStatusDetailTable(List<FasihRekapRow> allRows) {
    // Terapkan filter status lalu urutan kolom.
    final rows = allRows.where(_statusRowMatchesFilter).toList();
    if (_statusSlsSortCol != null) {
      rows.sort((a, b) {
        final cmp = Comparable.compare(
          _statusSlsSortValue(a, _statusSlsSortCol!),
          _statusSlsSortValue(b, _statusSlsSortCol!),
        );
        return _statusSlsAsc ? cmp : -cmp;
      });
    }

    if (rows.isEmpty) {
      return _buildEmptyState(
        _statusFilter == null
            ? 'Belum ada wilayah untuk ditampilkan.'
            : 'Tidak ada wilayah berstatus '
                  '"${_statusFilterLabel(_statusFilter!)}".',
      );
    }

    var totTarget = 0;
    var totSubmitted = 0;
    for (final row in rows) {
      totTarget += _targetOf(row);
      final b = _breakdownOf(
        row.statusCounts,
        row.totalAssignment,
        row.totalTerkirim,
      );
      totSubmitted += b.submitted;
    }

    const headerStyle = TextStyle(fontWeight: FontWeight.w600, fontSize: 12);

    return _fullWidthScroll(
      DataTable(
        showCheckboxColumn: false,
        horizontalMargin: 12,
        columnSpacing: 18,
        headingRowHeight: 48,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 60,
        sortColumnIndex: _statusSlsSortCol,
        sortAscending: _statusSlsAsc,
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
        columns: [
          _noColumn(),
          DataColumn(
            onSort: _onStatusSlsSort,
            label: const Text('SLS', style: headerStyle),
          ),
          DataColumn(
            onSort: _onStatusSlsSort,
            label: const Text('Sub', style: headerStyle),
          ),
          DataColumn(
            onSort: _onStatusSlsSort,
            label: const Text('Nama SLS', style: headerStyle),
          ),
          DataColumn(
            onSort: _onStatusSlsSort,
            label: const Text('Status', style: headerStyle),
          ),
          _numColumn('Target', onSort: _onStatusSlsSort),
          _numColumn('Submitted', onSort: _onStatusSlsSort),
          _numColumn('%', onSort: _onStatusSlsSort),
        ],
        rows:
            rows.asMap().entries.map((entry) {
              final row = entry.value;
              final b = _breakdownOf(
                row.statusCounts,
                row.totalAssignment,
                row.totalTerkirim,
              );
              final target = _targetOf(row);
              final kodeSls = row.unitId.length >= 14
                  ? row.unitId.substring(10, 14)
                  : row.unitId;
              final kodeSubsls = row.unitId.length >= 16
                  ? row.unitId.substring(14, 16)
                  : '-';
              return DataRow(
                cells: [
                  _noCell(entry.key + 1),
                  DataCell(
                    Text(
                      kodeSls,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F4C81),
                      ),
                    ),
                  ),
                  DataCell(Text(kodeSubsls)),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        row.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  DataCell(_statusChip(row)),
                  _numCell(target, color: const Color(0xFF0F4C81)),
                  _numCell(b.submitted, color: const Color(0xFF1D8F5A)),
                  _percentCell(b.submitted, target),
                ],
              );
            }).toList()..add(
              DataRow(
                color: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
                cells: [
                  const DataCell(Text('')),
                  _totalLabelCell('Total'),
                  const DataCell(Text('')),
                  DataCell(
                    Text(
                      '${rows.length} SLS/Sub-SLS',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const DataCell(Text('')),
                  _numCell(totTarget, color: const Color(0xFF0F4C81)),
                  _numCell(totSubmitted, color: const Color(0xFF1D8F5A)),
                  _percentCell(totSubmitted, totTarget),
                ],
              ),
            ),
      ),
    );
  }

  /// Persentase capaian submitted terhadap target prelist.
  /// Jika target belum diisi (0), tampilkan '-'.
  DataCell _percentCell(int submitted, int target) {
    if (target <= 0) {
      return DataCell(Text('-', style: TextStyle(color: Colors.blueGrey[300])));
    }
    final percent = submitted / target;
    return DataCell(
      Text(
        '${(percent * 100).toStringAsFixed(2)}%',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: _progressColor(percent),
        ),
      ),
    );
  }

  /// Bungkus tabel agar minimal selebar layar (mengisi seluruh lebar),
  /// namun tetap bisa digeser horizontal jika isinya lebih lebar.
  Widget _fullWidthScroll(Widget table) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: table,
        ),
      ),
    );
  }

  DataColumn _numColumn(
    String label, {
    bool sortable = true,
    void Function(int, bool)? onSort,
  }) {
    return DataColumn(
      numeric: true,
      onSort: onSort ?? (sortable ? _onSort : null),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }

  /// Urutkan salinan baris sesuai arah sort aktif.
  void _sortRows(
    List<FasihRekapRow> rows,
    Comparable<dynamic> Function(FasihRekapRow) selector,
  ) {
    rows.sort((a, b) {
      final cmp = Comparable.compare(selector(a), selector(b));
      return _sortAscending ? cmp : -cmp;
    });
  }

  DataCell _numCell(int value, {Color? color}) {
    return DataCell(
      Text(
        value.toString(),
        style: TextStyle(fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  /// Kolom "No": nomor urut tampilan, tidak bisa di-sort agar selalu 1..N
  /// dari atas ke bawah mengikuti urutan baris yang sedang tampil.
  DataColumn _noColumn() {
    return const DataColumn(
      label: Text(
        'No',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }

  DataCell _noCell(int number) {
    return DataCell(
      Text(
        '$number',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.blueGrey[400],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: Colors.blueGrey[200]),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Color _progressColor(double percent) {
    if (percent >= 0.999) return const Color(0xFF1D8F5A);
    if (percent >= 0.6) return const Color(0xFF2D77D0);
    if (percent >= 0.3) return Colors.orange[700]!;
    return Colors.red[400]!;
  }
}

class _Riil {
  int kkRiil = 0;
  int usahaRiil = 0;
  int usahaDitemukan = 0;
  int tidakDitemukan = 0;

  void add(ProgresSlsRow r) {
    kkRiil += r.kkRiil;
    usahaRiil += r.usahaRiil;
    usahaDitemukan += r.usahaDitemukan;
    tidakDitemukan += r.kkTidakDitemukan + r.usahaTidakDitemukan;
  }
}

class _Tier {
  final String label;
  final String sub;
  final Color color;

  const _Tier({required this.label, required this.sub, required this.color});
}

class _StatusBreakdown {
  final int open;
  final int draft;
  final int submitted;

  const _StatusBreakdown({
    required this.open,
    required this.draft,
    required this.submitted,
  });
}

/// Kelompok wilayah (SLS/sub-SLS) milik satu petugas, untuk rekap status per
/// petugas di tab Status.
class _PetugasWilayahGroup {
  final String name;
  final String email;
  final List<FasihRekapRow> wilayah;

  const _PetugasWilayahGroup({
    required this.name,
    required this.email,
    required this.wilayah,
  });
}
