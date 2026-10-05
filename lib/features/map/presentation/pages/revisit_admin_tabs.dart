import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/revisit_models.dart';
import '../../data/services/revisit_service.dart';
import '../widgets/revisit_widgets.dart';
import 'revisit_impor_page.dart';
import 'revisit_page.dart';
import 'revisit_petugas_detail_page.dart';

/// Target jumlah anggota tim revisit (informasi saja, tidak dibatasi).
const int _targetTim = 26;

// ── Rekap (admin) ────────────────────────────────────────────────────────────

/// Rekap KUMULATIF tim revisit: berapa dari berapa SLS sudah dikunjungi,
/// total didata/submit/sisa potensi, dan grafik progres per "hari ke-"
/// alokasi (bukan per tanggal upload laporan). Klik petugas untuk detail
/// dan laporan hariannya.
class RevisitRekapTab extends StatefulWidget {
  const RevisitRekapTab({super.key});

  @override
  State<RevisitRekapTab> createState() => _RevisitRekapTabState();
}

class _RevisitRekapTabState extends State<RevisitRekapTab>
    with AutomaticKeepAliveClientMixin {
  final RevisitService _service = RevisitService();

  bool _loading = true;
  String? _error;
  List<RevisitRekapPetugas> _petugas = [];
  List<RevisitProgresHariKe> _hariKe = [];

  /// Tampilan daftar petugas: kartu (default), tabel, atau matriks.
  _Tampilan _tampilan = _Tampilan.kartu;
  List<RevisitMatriksSel> _matriks = [];
  int _sortKolom = 0;
  bool _sortNaik = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _petugas.isEmpty;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.fetchRekapPetugas(),
        _service.fetchProgresHariKe(),
        _service.fetchMatriksHari(),
      ]);
      if (!mounted) return;
      setState(() {
        _petugas = results[0] as List<RevisitRekapPetugas>;
        _hariKe = results[1] as List<RevisitProgresHariKe>;
        _matriks = results[2] as List<RevisitMatriksSel>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int _sum(int Function(RevisitRekapPetugas) f) =>
      _petugas.fold<int>(0, (s, p) => s + f(p));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return RevisitErrorView(error: _error!, onRetry: _load);

    final totalSls = _sum((p) => p.jumlahSls);
    final slsDilapor = _sum((p) => p.slsDilapor);
    final persen = totalSls == 0 ? 0.0 : slsDilapor / totalSls;
    final timKeys = {for (final p in _petugas) p.tim}.toList()
      ..sort(_compareTim);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          RevisitHeaderCard(
            title: 'Rekap Revisit',
            subtitle: 'Kumulatif sejak awal · ${_petugas.length} petugas',
            trailing: IconButton(
              color: Colors.white,
              tooltip: 'Muat ulang',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
            stats: [
              ('$slsDilapor/$totalSls', 'SLS dikunjungi'),
              ('${_sum((p) => p.totalDidata)}', 'didata'),
              ('${_sum((p) => p.totalSubmit)}', 'submit'),
              ('${_sum((p) => p.sisaBelumDidata)}', 'potensi belum didata'),
            ],
          ),
          const SizedBox(height: 12),
          _progresKeseluruhan(slsDilapor, totalSls, persen),
          const SizedBox(height: 12),
          RevisitHariKeChart(progres: _hariKe),
          const SizedBox(height: 16),
          _judulPetugas(),
          if (_petugas.isEmpty)
            const RevisitEmptyView(
              message:
                  'Tim revisit masih kosong. Tambahkan petugas di tab Alokasi.',
            )
          else if (_tampilan == _Tampilan.tabel)
            _tabelPetugas()
          else if (_tampilan == _Tampilan.matriks)
            _matriksPetugas()
          else
            for (final key in timKeys) ...[
              _timHeader(key),
              for (final p in _petugas.where((p) => p.tim == key)) ...[
                _petugasCard(p),
                const SizedBox(height: 10),
              ],
            ],
        ],
      ),
    );
  }

  Widget _progresKeseluruhan(int dilapor, int total, double persen) {
    final selesai = _sum((p) => p.slsSelesai);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'SLS dikunjungi',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
              Text(
                '$dilapor dari $total (${(persen * 100).round()}%)',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: revisitPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: persen,
              minHeight: 10,
              backgroundColor: const Color(0xFFE2E8F0),
              color: persen >= 1 ? revisitWarnaSubmit : revisitWarnaDidata,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$selesai SLS berstatus selesai · '
            '${_sum((p) => p.jumlahLaporan)} laporan · '
            '${_sum((p) => p.jumlahFoto)} foto',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _judulPetugas() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Petugas',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
          SegmentedButton<_Tampilan>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
            ),
            segments: const [
              ButtonSegment(
                value: _Tampilan.kartu,
                icon: Icon(Icons.view_agenda_outlined, size: 18),
                tooltip: 'Kartu',
              ),
              ButtonSegment(
                value: _Tampilan.tabel,
                icon: Icon(Icons.table_rows_outlined, size: 18),
                tooltip: 'Tabel',
              ),
              ButtonSegment(
                value: _Tampilan.matriks,
                icon: Icon(Icons.grid_on_rounded, size: 18),
                tooltip: 'Matriks per hari',
              ),
            ],
            selected: {_tampilan},
            onSelectionChanged: (v) => setState(() => _tampilan = v.first),
          ),
        ],
      ),
    );
  }

  /// Urutan baris tabel sesuai kolom sort aktif.
  List<RevisitRekapPetugas> get _petugasTerurut {
    int cmp(RevisitRekapPetugas a, RevisitRekapPetugas b) {
      switch (_sortKolom) {
        case 1:
          final c = _compareTim(a.tim, b.tim);
          return c != 0 ? c : a.nama.compareTo(b.nama);
        case 2:
          return a.slsDilapor.compareTo(b.slsDilapor);
        case 3:
          return a.persenSls.compareTo(b.persenSls);
        case 4:
          return a.totalDidata.compareTo(b.totalDidata);
        case 5:
          return a.totalSubmit.compareTo(b.totalSubmit);
        case 6:
          return a.sisaBelumDidata.compareTo(b.sisaBelumDidata);
        case 7:
          return a.jumlahLaporan.compareTo(b.jumlahLaporan);
        case 8:
          return a.jumlahFoto.compareTo(b.jumlahFoto);
        case 9:
          final ta = a.tanggalTerakhir;
          final tb = b.tanggalTerakhir;
          if (ta == null || tb == null) {
            return ta == tb ? 0 : (ta == null ? -1 : 1);
          }
          return ta.compareTo(tb);
      }
      return a.nama.compareTo(b.nama);
    }

    final list = List.of(_petugas)..sort(cmp);
    return _sortNaik ? list : list.reversed.toList();
  }

  Widget _tabelPetugas() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // Tabel melebar penuh bila muat; menggulir hanya bila kolomnya
          // lebih lebar dari kartu.
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: c.maxWidth),
            child: DataTable(
              sortColumnIndex: _sortKolom,
              sortAscending: _sortNaik,
              headingRowHeight: 40,
              dataRowMinHeight: 42,
              dataRowMaxHeight: 52,
              columnSpacing: 20,
              headingTextStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: revisitPrimary,
              ),
              dataTextStyle: const TextStyle(
                fontSize: 13,
                color: Color(0xFF334155),
              ),
              columns: [
                _kolom('Nama'),
                _kolom('Tim'),
                _kolom('SLS', numerik: true),
                _kolom('%', numerik: true),
                _kolom('Didata', numerik: true),
                _kolom('Submit', numerik: true),
                _kolom('Belum', numerik: true),
                _kolom('Laporan', numerik: true),
                _kolom('Foto', numerik: true),
                _kolom('Terakhir'),
              ],
              rows: [
                for (final p in _petugasTerurut)
                  DataRow(
                    onSelectChanged: (_) => _openDetail(p),
                    cells: [
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              p.nama,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              revisitRoleLabel(p.role),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Text(p.tim.isEmpty ? '-' : revisitTimLabel(p.tim)),
                      ),
                      DataCell(Text('${p.slsDilapor}/${p.jumlahSls}')),
                      DataCell(
                        Text(
                          '${(p.persenSls * 100).round()}%',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: p.persenSls >= 1
                                ? revisitWarnaSubmit
                                : p.persenSls == 0
                                ? revisitWarnaSisa
                                : revisitWarnaDidata,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${p.totalDidata}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: revisitWarnaDidata,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${p.totalSubmit}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: revisitWarnaSubmit,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${p.sisaBelumDidata}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: p.sisaBelumDidata > 0
                                ? revisitWarnaSisa
                                : revisitWarnaSubmit,
                          ),
                        ),
                      ),
                      DataCell(Text('${p.jumlahLaporan}')),
                      DataCell(Text('${p.jumlahFoto}')),
                      DataCell(
                        Text(
                          p.tanggalTerakhir == null
                              ? '-'
                              : revisitDateLabel(p.tanggalTerakhir!),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Matriks petugas × hari ke-: sel berisi "SLS dilapor / SLS jadwal",
  /// sehingga sel yang belum dilapor langsung terlihat.
  Widget _matriksPetugas() {
    const lebarNama = 150.0;
    const lebarSel = 58.0;

    final hariList = {for (final m in _matriks) m.hariKe}.toList()
      ..sort((a, b) {
        if (a == null || b == null) return a == null ? 1 : -1;
        return a.compareTo(b);
      });
    if (hariList.isEmpty) {
      return const RevisitEmptyView(
        message: 'Belum ada alokasi dengan hari ke-.',
      );
    }

    final byPetugas = <String, Map<int?, RevisitMatriksSel>>{};
    for (final m in _matriks) {
      byPetugas.putIfAbsent(m.petugasId, () => {})[m.hariKe] = m;
    }
    final urut = List.of(_petugas)
      ..sort((a, b) {
        final c = _compareTim(a.tim, b.tim);
        return c != 0 ? c : a.nama.compareTo(b.nama);
      });

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Isi sel: didata / submit',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _legendaSel(_merahBelum, 'Belum lapor'),
              _legendaSel(revisitWarnaDidata, 'Sebagian SLS dilapor'),
              _legendaSel(revisitWarnaSubmit, 'Semua SLS dilapor'),
              _legendaSel(const Color(0xFFE2E8F0), 'Tidak ada jadwal'),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(width: lebarNama, child: Text('')),
                    for (final h in hariList)
                      SizedBox(
                        width: lebarSel,
                        child: Center(
                          child: Text(
                            h == null ? '–' : 'H$h',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: revisitPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final p in urut)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: lebarNama,
                          child: InkWell(
                            onTap: () => _openDetail(p),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.nama,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  p.tim.isEmpty
                                      ? revisitRoleLabel(p.role)
                                      : revisitTimLabel(p.tim),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        for (final h in hariList)
                          _selMatriks(byPetugas[p.petugasId]?[h], lebarSel),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const Color _merahBelum = Color(0xFFC62828);

  Widget _legendaSel(Color warna, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: warna.withValues(alpha: 0.25),
            border: Border.all(color: warna.withValues(alpha: 0.7)),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _selMatriks(RevisitMatriksSel? sel, double lebar) {
    final kosong = sel == null || sel.jumlahSls == 0;
    // Merah = belum ada laporan sama sekali untuk jadwal hari itu.
    final warna = kosong
        ? const Color(0xFFE2E8F0)
        : sel.belumLapor
        ? _merahBelum
        : sel.lengkap
        ? revisitWarnaSubmit
        : revisitWarnaDidata;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: kosong
            ? 'Tidak ada SLS terjadwal'
            : '${sel.totalDidata} didata · ${sel.totalSubmit} submit\n'
                  '${sel.slsDilapor}/${sel.jumlahSls} SLS dilapor · '
                  '${sel.slsSelesai} selesai',
        child: Container(
          width: lebar - 4,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: warna.withValues(alpha: kosong ? 0.5 : 0.18),
            border: Border.all(color: warna.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: FittedBox(
            child: Text(
              kosong ? '–' : '${sel.totalDidata}/${sel.totalSubmit}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kosong ? const Color(0xFF94A3B8) : warna,
              ),
            ),
          ),
        ),
      ),
    );
  }

  DataColumn _kolom(String label, {bool numerik = false}) {
    return DataColumn(
      label: Text(label),
      numeric: numerik,
      onSort: (i, naik) => setState(() {
        _sortKolom = i;
        _sortNaik = naik;
      }),
    );
  }

  Widget _timHeader(String key) {
    final anggota = _petugas.where((p) => p.tim == key).toList();
    int sum(int Function(RevisitRekapPetugas) f) =>
        anggota.fold<int>(0, (s, p) => s + f(p));
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          const Icon(Icons.groups_rounded, size: 18, color: revisitPrimary),
          const SizedBox(width: 6),
          Text(
            revisitTimLabel(key),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: revisitPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${anggota.length} orang · '
              '${sum((p) => p.slsDilapor)}/${sum((p) => p.jumlahSls)} SLS · '
              '${sum((p) => p.totalDidata)} didata · '
              '${sum((p) => p.totalSubmit)} submit',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _petugasCard(RevisitRekapPetugas p) {
    final belum = p.slsDilapor == 0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openDetail(p),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: belum
                        ? const Color(0xFFFFF3D6)
                        : const Color(0xFFE3F2E7),
                    child: Text(
                      revisitRoleLabel(p.role),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: belum
                            ? const Color(0xFFB45309)
                            : revisitWarnaSubmit,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.nama,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          [
                            '${p.slsDilapor}/${p.jumlahSls} SLS dikunjungi',
                            '${p.slsSelesai} selesai',
                            if (p.tanggalTerakhir != null)
                              'terakhir ${revisitDateLabel(p.tanggalTerakhir!)}',
                          ].join(' · '),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: p.persenSls,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFE2E8F0),
                        color: p.persenSls >= 1
                            ? revisitWarnaSubmit
                            : revisitWarnaDidata,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(p.persenSls * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                  ),
                  children: [
                    _angka('${p.totalDidata}', revisitWarnaDidata),
                    const TextSpan(text: ' didata · '),
                    _angka('${p.totalSubmit}', revisitWarnaSubmit),
                    const TextSpan(text: ' submit · '),
                    _angka(
                      '${p.sisaBelumDidata}',
                      p.sisaBelumDidata > 0
                          ? revisitWarnaSisa
                          : revisitWarnaSubmit,
                    ),
                    const TextSpan(text: ' belum didata · '),
                    TextSpan(text: '${p.jumlahFoto} foto'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextSpan _angka(String v, Color c) => TextSpan(
    text: v,
    style: TextStyle(fontWeight: FontWeight.w800, color: c),
  );

  Future<void> _openDetail(RevisitRekapPetugas p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RevisitPetugasDetailPage(
          petugas: RevisitPetugas(
            petugasId: p.petugasId,
            nama: p.nama,
            email: '',
            role: p.role,
            isRevisit: true,
            jumlahSls: p.jumlahSls,
            tim: p.tim,
          ),
          tanggal: DateTime.now(),
        ),
      ),
    );
    if (mounted) _load();
  }
}

// ── Alokasi (admin) ──────────────────────────────────────────────────────────

enum _Tampilan { kartu, tabel, matriks }

enum _AlokasiMode { tim, sls }

enum _SlsFilter { semua, belum, sudah }

class RevisitAlokasiTab extends StatefulWidget {
  const RevisitAlokasiTab({super.key});

  @override
  State<RevisitAlokasiTab> createState() => _RevisitAlokasiTabState();
}

class _RevisitAlokasiTabState extends State<RevisitAlokasiTab>
    with AutomaticKeepAliveClientMixin {
  final RevisitService _service = RevisitService();
  final TextEditingController _search = TextEditingController();

  _AlokasiMode _mode = _AlokasiMode.tim;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String _query = '';

  List<RevisitPetugas> _petugas = [];
  List<RevisitAlokasiItem> _sls = [];

  // Filter tim
  bool _hanyaTim = false;

  // Filter SLS
  String? _kec;
  String? _desa;
  String? _filterPetugasId;
  String? _filterHari;
  _SlsFilter _slsFilter = _SlsFilter.semua;
  final Set<String> _selected = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _petugas.isEmpty;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.fetchPetugas(),
        _service.fetchAlokasi(),
      ]);
      if (!mounted) return;
      setState(() {
        _petugas = results[0] as List<RevisitPetugas>;
        _sls = results[1] as List<RevisitAlokasiItem>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<RevisitPetugas> get _tim => _petugas.where((p) => p.isRevisit).toList();

  void _showSnack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _run(Future<void> Function() action, String sukses) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      if (mounted) _showSnack(sukses);
    } catch (e) {
      if (mounted) _showSnack('Gagal: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleTim(RevisitPetugas p, bool aktif) async {
    if (!aktif && p.jumlahSls > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Keluarkan dari tim?'),
          content: Text(
            '${p.nama} memegang ${p.jumlahSls} SLS. Alokasi SLS tersebut akan '
            'dilepas. Laporan yang sudah masuk tetap tersimpan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Keluarkan'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _run(
      () => _service.setPetugasRevisit(p.petugasId, aktif),
      aktif ? '${p.nama} masuk tim revisit' : '${p.nama} dikeluarkan dari tim',
    );
  }

  Future<void> _alokasikanTerpilih() async {
    final tim = _tim;
    if (tim.isEmpty) {
      _showSnack('Tambahkan petugas ke tim revisit dulu', error: true);
      return;
    }
    final pilihan = await showModalBottomSheet<(RevisitPetugas, int?, bool)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _PilihPetugasSheet(tim: tim),
    );
    if (pilihan == null) return;
    final (target, hari, ganti) = pilihan;
    final kode = _selected.toList();
    await _run(
      () async {
        await _service.setAlokasi(
          kode,
          target.petugasId,
          hariKe: hari,
          ganti: ganti,
        );
        _selected.clear();
      },
      '${kode.length} SLS ${ganti ? 'diganti ke' : 'dialokasikan ke'} '
      '${target.nama}${hari != null ? ' (hari ke-$hari)' : ''}',
    );
  }

  /// Hapus satu jadwal (SLS + hari + petugas) lewat chip di daftar SLS.
  Future<void> _hapusJadwal(RevisitAlokasiItem s, RevisitJadwal j) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus jadwal ini?'),
        content: Text(
          '${s.slsLabel} · ${j.hariKe == 0 ? 'hari belum ditentukan' : 'hari ke-${j.hariKe}'}'
          ' · ${j.nama}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => _service.setAlokasi(
        [s.kodeSls],
        j.petugasId,
        hariKe: j.hariKe,
        lepasPetugas: true,
      ),
      'Jadwal ${j.label} dihapus',
    );
  }

  Future<void> _lepasTerpilih() async {
    final kode = _selected.toList();
    await _run(() async {
      await _service.setAlokasi(kode, null);
      _selected.clear();
    }, 'Alokasi ${kode.length} SLS dilepas');
  }

  Future<void> _imporCepat() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RevisitImporPage(petugas: _petugas, sls: _sls),
      ),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _editTim(RevisitPetugas p) async {
    final existing = {
      for (final x in _tim)
        if (x.tim.isNotEmpty) x.tim,
    }.toList()..sort(_compareTim);
    final controller = TextEditingController(text: p.tim);
    final hasil = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tim ${p.nama}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nama / nomor tim',
                hintText: 'mis. 1',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            if (existing.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in existing)
                    ActionChip(
                      label: Text(
                        '${revisitTimLabel(t)} '
                        '(${_tim.where((x) => x.tim == t).length})',
                      ),
                      onPressed: () => Navigator.pop(ctx, t),
                    ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('Kosongkan'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (hasil == null) return;
    await _run(
      () => _service.setTim(p.petugasId, hasil),
      hasil.trim().isEmpty
          ? 'Tim ${p.nama} dikosongkan'
          : '${p.nama} masuk ${revisitTimLabel(hasil)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return RevisitErrorView(error: _error!, onRetry: _load);

    final teralokasi = _sls.where((s) => s.isAllocated).length;
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SegmentedButton<_AlokasiMode>(
                segments: [
                  ButtonSegment(
                    value: _AlokasiMode.tim,
                    icon: const Icon(Icons.groups_rounded),
                    label: Text('Tim (${_tim.length}/$_targetTim)'),
                  ),
                  ButtonSegment(
                    value: _AlokasiMode.sls,
                    icon: const Icon(Icons.map_rounded),
                    label: Text('SLS ($teralokasi/${_sls.length})'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() {
                  _mode = v.first;
                  _query = '';
                  _search.clear();
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: RevisitSearchField(
                      controller: _search,
                      hint: _mode == _AlokasiMode.tim
                          ? 'Cari nama / email / tim'
                          : 'Cari SLS / desa / petugas',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _imporCepat,
                    icon: const Icon(Icons.content_paste_go_rounded),
                    label: const Text('Impor Cepat'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _mode == _AlokasiMode.tim ? _buildTim() : _buildSls(),
              ),
            ),
          ],
        ),
        if (_busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  // ── Mode Tim ──

  Widget _buildTim() {
    final q = _query.trim().toLowerCase();
    final list = _petugas.where((p) {
      if (_hanyaTim && !p.isRevisit) return false;
      if (q.isEmpty) return true;
      return '${p.nama} ${p.email} ${revisitTimLabel(p.tim)}'
          .toLowerCase()
          .contains(q);
    }).toList();

    // Mode "Hanya tim": kelompokkan per tim (informasi 2 orang per tim).
    final groups = <String, List<RevisitPetugas>>{};
    if (_hanyaTim) {
      for (final p in list) {
        groups.putIfAbsent(p.tim, () => []).add(p);
      }
    }
    final timKeys = groups.keys.toList()..sort(_compareTim);
    final jumlahTim = {
      for (final p in _tim)
        if (p.tim.isNotEmpty) p.tim,
    }.length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_tim.length} petugas dalam $jumlahTim tim. '
                'Alokasi tetap per orang; tim hanya informasi.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ),
            FilterChip(
              label: const Text('Hanya tim'),
              selected: _hanyaTim,
              onSelected: (v) => setState(() => _hanyaTim = v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_hanyaTim)
          for (final key in timKeys) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Row(
                children: [
                  Text(
                    revisitTimLabel(key),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: revisitPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${groups[key]!.length} orang · '
                    '${groups[key]!.fold<int>(0, (s, p) => s + p.jumlahSls)} SLS',
                    style: TextStyle(
                      fontSize: 12,
                      color: key.isNotEmpty && groups[key]!.length != 2
                          ? const Color(0xFFB45309)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            for (final p in groups[key]!) _petugasTile(p),
          ]
        else
          for (final p in list) _petugasTile(p),
        if (list.isEmpty) const RevisitEmptyView(message: 'Tidak ada petugas.'),
      ],
    );
  }

  Widget _petugasTile(RevisitPetugas p) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SwitchListTile(
        value: p.isRevisit,
        onChanged: _busy ? null : (v) => _toggleTim(p, v),
        title: Text(
          p.nama,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${revisitRoleLabel(p.role)}'
              '${p.email.isNotEmpty ? ' · ${p.email}' : ''}'
              '${p.isRevisit ? ' · ${p.jumlahSls} SLS' : ''}',
            ),
            if (p.isRevisit)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.groups_rounded, size: 16),
                  label: Text(
                    p.tim.isEmpty ? 'Atur tim' : revisitTimLabel(p.tim),
                  ),
                  onPressed: _busy ? null : () => _editTim(p),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Mode SLS ──

  List<RevisitAlokasiItem> get _slsFiltered {
    final q = _query.trim().toLowerCase();
    return _sls.where((s) {
      if (_kec != null && s.nmKec != _kec) return false;
      if (_desa != null && s.nmDesa != _desa) return false;
      if (_filterPetugasId != null && !s.dipegang(_filterPetugasId!)) {
        return false;
      }
      if (_filterHari != null &&
          !s.hariList.map((h) => '$h').contains(_filterHari)) {
        return false;
      }
      if (_slsFilter == _SlsFilter.belum && s.isAllocated) return false;
      if (_slsFilter == _SlsFilter.sudah && !s.isAllocated) return false;
      if (q.isEmpty) return true;
      return [
        s.slsLabel,
        s.kodeSls,
        s.nmDesa,
        s.nmKec,
        for (final j in s.jadwal) j.nama,
        s.pmlNama,
        s.pplNama,
      ].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  Widget _buildSls() {
    final kecList = {
      for (final s in _sls) s.nmKec,
    }.where((e) => e.isNotEmpty).toList()..sort();
    final desaList = {
      for (final s in _sls)
        if (_kec == null || s.nmKec == _kec) s.nmDesa,
    }.where((e) => e.isNotEmpty).toList()..sort();
    final items = _slsFiltered;
    final allSelected =
        items.isNotEmpty && items.every((s) => _selected.contains(s.kodeSls));

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              _dropdownChip(
                label: 'Kecamatan',
                value: _kec,
                options: kecList,
                onChanged: (v) => setState(() {
                  _kec = v;
                  _desa = null;
                }),
              ),
              const SizedBox(width: 8),
              _dropdownChip(
                label: 'Desa',
                value: _desa,
                options: desaList,
                onChanged: (v) => setState(() => _desa = v),
              ),
              const SizedBox(width: 8),
              _dropdownChip(
                label: 'Petugas',
                value: _filterPetugasId,
                options: [for (final p in _tim) p.petugasId],
                display: (id) {
                  final p = _tim.where((p) => p.petugasId == id).firstOrNull;
                  if (p == null) return id;
                  return p.tim.isEmpty
                      ? p.nama
                      : '${p.nama} (${revisitTimLabel(p.tim)})';
                },
                onChanged: (v) => setState(() => _filterPetugasId = v),
              ),
              const SizedBox(width: 8),
              _dropdownChip(
                label: 'Hari',
                value: _filterHari,
                options: [
                  for (final h in {
                    for (final s in _sls) ...s.hariList,
                  }.toList()..sort())
                    '$h',
                ],
                display: (h) => h == '0' ? 'Belum ditentukan' : 'Hari ke-$h',
                onChanged: (v) => setState(() => _filterHari = v),
              ),
              const SizedBox(width: 8),
              for (final f in _SlsFilter.values) ...[
                ChoiceChip(
                  label: Text(switch (f) {
                    _SlsFilter.semua => 'Semua',
                    _SlsFilter.belum => 'Belum dialokasi',
                    _SlsFilter.sudah => 'Sudah dialokasi',
                  }),
                  selected: _slsFilter == f,
                  onSelected: (_) => setState(() => _slsFilter = f),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Checkbox(
                value: allSelected,
                onChanged: items.isEmpty
                    ? null
                    : (v) => setState(() {
                        for (final s in items) {
                          v == true
                              ? _selected.add(s.kodeSls)
                              : _selected.remove(s.kodeSls);
                        }
                      }),
              ),
              Expanded(
                child: Text(
                  '${items.length} SLS'
                  '${_selected.isNotEmpty ? ' · ${_selected.length} dipilih' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (_selected.isNotEmpty)
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('Bersihkan'),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            itemCount: items.length,
            itemBuilder: (context, i) => _slsTile(items[i]),
          ),
        ),
        if (_selected.isNotEmpty)
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 8)],
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _lepasTerpilih,
                    icon: const Icon(Icons.link_off_rounded),
                    label: const Text('Lepas'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _alokasikanTerpilih,
                      style: FilledButton.styleFrom(
                        backgroundColor: revisitPrimary,
                      ),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: Text('Alokasikan ${_selected.length} SLS'),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _slsTile(RevisitAlokasiItem s) {
    final selected = _selected.contains(s.kodeSls);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      color: selected ? const Color(0xFFE8F1FB) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: CheckboxListTile(
        value: selected,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (v) => setState(() {
          v == true ? _selected.add(s.kodeSls) : _selected.remove(s.kodeSls);
        }),
        title: Text(
          s.slsLabel,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${revisitWilayahLabel(s.nmDesa, s.nmKec)} · PPL ${s.pplNama}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            if (s.isAllocated)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.event_available_rounded,
                      size: 15,
                      color: Color(0xFF2E7D32),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Sudah dijadwalkan '
                      '${{for (final j in s.jadwal) j.hariKe}.length} hari'
                      ' · ${s.jadwal.length} petugas-hari',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ],
                ),
              ),
            // Satu chip per jadwal: hari + petugas pemiliknya.
            s.isAllocated
                ? Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final j in s.jadwal)
                        InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: _busy ? null : () => _hapusJadwal(s, j),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE3F2E7),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              j.label,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF2E7D32),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : const Text(
                    'Belum dialokasi',
                    style: TextStyle(color: Color(0xFFB45309)),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _dropdownChip({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    String Function(String)? display,
  }) {
    final show = display ?? (v) => v;
    return PopupMenuButton<String>(
      tooltip: label,
      onSelected: (v) => onChanged(v.isEmpty ? null : v),
      itemBuilder: (_) => [
        PopupMenuItem(value: '', child: Text('Semua $label')),
        for (final o in options) PopupMenuItem(value: o, child: Text(show(o))),
      ],
      child: Chip(
        avatar: Icon(
          Icons.filter_list_rounded,
          size: 16,
          color: value == null ? null : revisitPrimary,
        ),
        label: Text(value == null ? label : show(value)),
        backgroundColor: value == null ? Colors.white : const Color(0xFFE8F1FB),
      ),
    );
  }
}

/// Urut label tim: angka dulu secara numerik ("2" < "10"), lalu teks.
int _compareTim(String a, String b) {
  final na = int.tryParse(a.replaceAll(RegExp(r'\D'), ''));
  final nb = int.tryParse(b.replaceAll(RegExp(r'\D'), ''));
  if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
  if (na != null && nb != null && na != nb) return na.compareTo(nb);
  return a.compareTo(b);
}

/// Pilih petugas tujuan + (opsional) hari ke- + mode.
/// Mengembalikan `(petugas, hariKe, ganti)`; `ganti` true = tukar petugas
/// pada (SLS, hari) itu, bukan menambah petugas kedua.
class _PilihPetugasSheet extends StatefulWidget {
  final List<RevisitPetugas> tim;

  const _PilihPetugasSheet({required this.tim});

  @override
  State<_PilihPetugasSheet> createState() => _PilihPetugasSheetState();
}

class _PilihPetugasSheetState extends State<_PilihPetugasSheet> {
  final TextEditingController _hari = TextEditingController();
  String _query = '';

  /// true = ganti (petugas lain pada SLS+hari itu dilepas).
  bool _ganti = false;

  @override
  void dispose() {
    _hari.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final list =
        widget.tim
            .where(
              (p) => '${p.nama} ${revisitTimLabel(p.tim)}'
                  .toLowerCase()
                  .contains(q),
            )
            .toList()
          ..sort((a, b) {
            final c = _compareTim(a.tim, b.tim);
            return c != 0 ? c : a.nama.compareTo(b.nama);
          });
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            const Text(
              'Alokasikan ke petugas',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Cari nama / tim',
                        prefixIcon: Icon(Icons.search_rounded),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: _hari,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Hari ke-',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                ),
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.person_add_alt_1_rounded, size: 16),
                    label: Text('Tambah'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.swap_horiz_rounded, size: 16),
                    label: Text('Ganti'),
                  ),
                ],
                selected: {_ganti},
                onSelectionChanged: (v) => setState(() => _ganti = v.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                _ganti
                    ? 'Ganti: petugas lain pada SLS & hari itu dilepas, '
                          'jadi jadwalnya bertukar.'
                    : 'Tambah: petugas ini ditambahkan tanpa melepas petugas '
                          'lain pada SLS & hari yang sama.\n'
                          'Kosongkan hari ke- untuk menjadwalkan banyak SLS '
                          'sekaligus (tanpa hari).',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final p = list[i];
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        revisitRoleLabel(p.role),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    title: Text(p.nama),
                    subtitle: Text(
                      '${p.tim.isEmpty ? 'Tanpa tim' : revisitTimLabel(p.tim)}'
                      ' · ${p.jumlahSls} SLS saat ini',
                    ),
                    onTap: () {
                      final hari = int.tryParse(_hari.text);
                      Navigator.pop(context, (
                        p,
                        hari == null || hari < 1 ? null : hari,
                        _ganti,
                      ));
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
