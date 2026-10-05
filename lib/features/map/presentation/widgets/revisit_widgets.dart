import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/revisit_models.dart';

/// Thumbnail foto revisit dari Drive. Tap = buka penampil layar penuh
/// (bila [gallery] diisi, bisa digeser ke foto lain dalam laporan yang sama).
class RevisitFotoThumb extends StatelessWidget {
  final RevisitFoto foto;
  final double size;
  final List<RevisitFoto>? gallery;

  const RevisitFotoThumb({
    super.key,
    required this.foto,
    this.size = 72,
    this.gallery,
  });

  @override
  Widget build(BuildContext context) {
    final list = gallery ?? [foto];
    return GestureDetector(
      onTap: () => showRevisitFotoViewer(
        context,
        list,
        initialIndex: list.indexWhere((f) => f.id == foto.id).clamp(0, 999),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          foto.thumbnailUrl(),
          width: size,
          height: size,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : _placeholder(const CircularProgressIndicator(strokeWidth: 2)),
          errorBuilder: (context, error, stackTrace) =>
              _placeholder(const Icon(Icons.broken_image_outlined)),
        ),
      ),
    );
  }

  Widget _placeholder(Widget child) {
    return Container(
      width: size,
      height: size,
      color: const Color(0xFFE2E8F0),
      alignment: Alignment.center,
      child: SizedBox(width: 20, height: 20, child: FittedBox(child: child)),
    );
  }
}

Future<void> showRevisitFotoViewer(
  BuildContext context,
  List<RevisitFoto> fotos, {
  int initialIndex = 0,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          _RevisitFotoViewer(fotos: fotos, initialIndex: initialIndex),
    ),
  );
}

class _RevisitFotoViewer extends StatefulWidget {
  final List<RevisitFoto> fotos;
  final int initialIndex;

  const _RevisitFotoViewer({required this.fotos, required this.initialIndex});

  @override
  State<_RevisitFotoViewer> createState() => _RevisitFotoViewerState();
}

class _RevisitFotoViewerState extends State<_RevisitFotoViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final foto = widget.fotos[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.fotos.length}'),
        actions: [
          IconButton(
            tooltip: 'Buka di Google Drive',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () => launchUrl(
              Uri.parse(foto.viewUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.fotos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Image.network(
              widget.fotos[i].thumbnailUrl(size: 1600),
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const CircularProgressIndicator(color: Colors.white),
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RevisitStatusBadge extends StatelessWidget {
  final String status;

  const RevisitStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final s = RevisitStatus.of(status);
    final color = s?.color ?? const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s?.icon ?? Icons.help_outline, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            s?.label ?? (status.isEmpty ? 'Belum ada laporan' : status),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartu satu laporan: SLS, status, jumlah dicek, catatan, dan foto.
class RevisitLaporanCard extends StatelessWidget {
  final RevisitLaporan laporan;
  final bool showPetugas;
  final bool showTanggal;
  final VoidCallback? onTap;

  const RevisitLaporanCard({
    super.key,
    required this.laporan,
    this.showPetugas = false,
    this.showTanggal = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final wilayah = [
      laporan.nmDesa,
      laporan.nmKec,
    ].where((e) => e.isNotEmpty).join(', ');
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          laporan.slsLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        if (wilayah.isNotEmpty)
                          Text(
                            wilayah,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  RevisitStatusBadge(status: laporan.status),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (showTanggal)
                    _meta(
                      Icons.event_rounded,
                      revisitDateLabel(laporan.tanggal),
                    ),
                  if (laporan.hariKe != null)
                    _meta(
                      Icons.calendar_view_day_rounded,
                      'Hari ke-${laporan.hariKe}',
                    ),
                  if (showPetugas)
                    _meta(
                      Icons.person_rounded,
                      '${laporan.petugasNama} '
                      '(${revisitRoleLabel(laporan.petugasRole)})',
                    ),
                  if (laporan.jumlahDidata != null)
                    _meta(
                      Icons.groups_2_rounded,
                      '${laporan.jumlahDidata} usaha/keluarga didata',
                    ),
                  if (laporan.jumlahSubmit != null)
                    _meta(
                      Icons.cloud_done_rounded,
                      '${laporan.jumlahSubmit} submit',
                    ),
                  if (laporan.jumlahBelumDidata != null)
                    _meta(
                      Icons.pending_actions_rounded,
                      '${laporan.jumlahBelumDidata} potensi belum didata',
                    ),
                  _meta(Icons.photo_rounded, '${laporan.foto.length} foto'),
                ],
              ),
              if (laporan.catatan.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  laporan.catatan,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    height: 1.35,
                  ),
                ),
              ],
              if (laporan.foto.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: laporan.foto.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => RevisitFotoThumb(
                      foto: laporan.foto[i],
                      gallery: laporan.foto,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF64748B)),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: Color(0xFF475569), fontSize: 12),
        ),
      ],
    );
  }
}

/// Warna angka progres (dipakai konsisten di semua tampilan revisit).
const Color revisitWarnaDidata = Color(0xFF0F4C81);
const Color revisitWarnaSubmit = Color(0xFF2E7D32);
const Color revisitWarnaSisa = Color(0xFFB45309);

/// Ringkasan angka satu SLS: didata, submit, sisa potensi + bar persentase
/// didata terhadap (didata + sisa).
class RevisitSlsAngka extends StatelessWidget {
  final RevisitTugas tugas;

  const RevisitSlsAngka({super.key, required this.tugas});

  @override
  Widget build(BuildContext context) {
    final persen = tugas.persenDidata;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            children: [
              _angka('${tugas.totalDidata}', revisitWarnaDidata),
              const TextSpan(text: ' didata · '),
              _angka('${tugas.totalSubmit}', revisitWarnaSubmit),
              const TextSpan(text: ' submit · '),
              _angka(
                tugas.belumDidata == null ? '-' : '${tugas.belumDidata}',
                (tugas.belumDidata ?? 0) > 0
                    ? revisitWarnaSisa
                    : revisitWarnaSubmit,
              ),
              const TextSpan(text: ' belum didata'),
            ],
          ),
        ),
        if (persen != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: persen,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFFDE7C8),
                    color: persen >= 1
                        ? revisitWarnaSubmit
                        : revisitWarnaDidata,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(persen * 100).round()}%',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  TextSpan _angka(String v, Color c) => TextSpan(
    text: v,
    style: TextStyle(fontWeight: FontWeight.w800, color: c),
  );
}

/// Kartu progres: didata & submit pada [tanggal], total kumulatif, sisa
/// potensi belum didata, rata-rata per hari kerja, dan grafik batang
/// didata vs submit [hari] hari terakhir s.d. [tanggal]. Tap batang untuk
/// memilih tanggal ([onSelect]).
class RevisitProgresCard extends StatelessWidget {
  final List<RevisitProgresHari> progres;
  final DateTime tanggal;
  final ValueChanged<DateTime>? onSelect;
  final int hari;

  const RevisitProgresCard({
    super.key,
    required this.progres,
    required this.tanggal,
    this.onSelect,
    this.hari = 14,
  });

  static DateTime _d(DateTime t) => DateTime(t.year, t.month, t.day);

  @override
  Widget build(BuildContext context) {
    final byDate = {for (final p in progres) _d(p.tanggal): p};
    final pilih = _d(tanggal);
    final hariIni = byDate[pilih];
    final sampai = progres.where((p) => !_d(p.tanggal).isAfter(pilih));
    final totalDidata = sampai.fold<int>(0, (s, p) => s + p.jumlahDidata);
    final totalSubmit = sampai.fold<int>(0, (s, p) => s + p.jumlahSubmit);
    final hariKerja = sampai.where((p) => p.jumlahLaporan > 0).length;
    final rata = hariKerja == 0 ? 0 : (totalDidata / hariKerja).round();
    final sisa = sampai.lastOrNull?.sisaBelumDidata ?? 0;

    final days = [
      for (var i = hari - 1; i >= 0; i--) pilih.subtract(Duration(days: i)),
    ];
    final maxVal = days
        .expand(
          (d) => [byDate[d]?.jumlahDidata ?? 0, byDate[d]?.jumlahSubmit ?? 0],
        )
        .fold<int>(0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
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
                  'Progres Usaha/Keluarga',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
              _legend(revisitWarnaDidata, 'Didata'),
              const SizedBox(width: 10),
              _legend(revisitWarnaSubmit, 'Submit'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _angka(
                '${hariIni?.jumlahDidata ?? 0}',
                'didata ${revisitDateLabel(pilih)}',
                revisitWarnaDidata,
              ),
              _angka(
                '${hariIni?.jumlahSubmit ?? 0}',
                'submit ${revisitDateLabel(pilih)}',
                revisitWarnaSubmit,
              ),
              _angka('$rata', 'rata-rata didata/hari', null),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _angka('$totalDidata', 'total didata', revisitWarnaDidata),
              _angka('$totalSubmit', 'total submit', revisitWarnaSubmit),
              _angka(
                '$sisa',
                'potensi belum didata',
                sisa > 0 ? revisitWarnaSisa : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in days)
                  Expanded(child: _batang(d, byDate[d], maxVal, d == pilih)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _angka(String value, String label, Color? color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color ?? const Color(0xFF334155),
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _batang(DateTime d, RevisitProgresHari? p, int maxVal, bool aktif) {
    const tinggiMaks = 58.0;
    final didata = p?.jumlahDidata ?? 0;
    final submit = p?.jumlahSubmit ?? 0;

    Widget bar(int v, Color c) {
      final h = maxVal == 0 ? 0.0 : tinggiMaks * v / maxVal;
      return Expanded(
        child: Container(
          height: v == 0 ? 2 : h.clamp(3.0, tinggiMaks),
          margin: const EdgeInsets.symmetric(horizontal: 0.5),
          decoration: BoxDecoration(
            color: v == 0
                ? const Color(0xFFE2E8F0)
                : c.withValues(alpha: aktif ? 1 : 0.45),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
          ),
        ),
      );
    }

    return Tooltip(
      message:
          '${revisitDateLabel(d, withDay: true)}\n'
          '$didata didata · $submit submit',
      child: InkWell(
        onTap: onSelect == null ? null : () => onSelect!(d),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (didata > 0)
                FittedBox(
                  child: Text(
                    '$didata',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: aktif ? FontWeight.w800 : FontWeight.w500,
                      color: aktif
                          ? revisitWarnaDidata
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  bar(didata, revisitWarnaDidata),
                  bar(submit, revisitWarnaSubmit),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${d.day}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: aktif ? FontWeight.w800 : FontWeight.w400,
                  color: aktif ? revisitWarnaDidata : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grafik progres per "hari ke-" alokasi (bukan per tanggal upload):
/// batang didata & submit, plus "SLS dilapor / SLS alokasi" di bawahnya.
class RevisitHariKeChart extends StatelessWidget {
  final List<RevisitProgresHariKe> progres;

  const RevisitHariKeChart({super.key, required this.progres});

  @override
  Widget build(BuildContext context) {
    if (progres.isEmpty) {
      return const SizedBox.shrink();
    }
    final maxVal = progres
        .expand((p) => [p.totalDidata, p.totalSubmit])
        .fold<int>(0, (a, b) => a > b ? a : b);
    final totalSls = progres.fold<int>(0, (s, p) => s + p.jumlahSls);
    final totalLapor = progres.fold<int>(0, (s, p) => s + p.slsDilapor);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
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
                  'Progres per Hari Ke-',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
              _legend(revisitWarnaDidata, 'Didata'),
              const SizedBox(width: 10),
              _legend(revisitWarnaSubmit, 'Submit'),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Berdasarkan jadwal alokasi · $totalLapor/$totalSls SLS sudah '
            'dikunjungi',
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          // Selebar kartu bila muat; menggulir hanya saat harinya banyak.
          LayoutBuilder(
            builder: (context, c) {
              const lebarMin = 44.0;
              final butuh = progres.length * lebarMin;
              final lebar = butuh <= c.maxWidth
                  ? c.maxWidth / progres.length
                  : lebarMin;
              final baris = Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final p in progres)
                    SizedBox(width: lebar, child: _batang(p, maxVal)),
                ],
              );
              return SizedBox(
                height: 124,
                child: butuh <= c.maxWidth
                    ? baris
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: baris,
                      ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _legend(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _batang(RevisitProgresHariKe p, int maxVal) {
    const tinggiMaks = 56.0;
    final selesai = p.jumlahSls > 0 && p.slsDilapor >= p.jumlahSls;

    Widget bar(int v, Color c) {
      final h = maxVal == 0 ? 0.0 : tinggiMaks * v / maxVal;
      return Expanded(
        child: Container(
          height: v == 0 ? 2 : h.clamp(3.0, tinggiMaks),
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: v == 0 ? const Color(0xFFE2E8F0) : c,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ),
      );
    }

    return Tooltip(
      message:
          '${p.labelPanjang}\n'
          '${p.slsDilapor}/${p.jumlahSls} SLS dikunjungi · '
          '${p.slsSelesai} selesai\n'
          '${p.totalDidata} didata · ${p.totalSubmit} submit · '
          '${p.sisaBelumDidata} belum didata',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FittedBox(
              child: Text(
                '${p.totalDidata}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: revisitWarnaDidata,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                bar(p.totalDidata, revisitWarnaDidata),
                bar(p.totalSubmit, revisitWarnaSubmit),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              p.label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF334155),
              ),
            ),
            Text(
              '${p.slsDilapor}/${p.jumlahSls}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: selesai ? revisitWarnaSubmit : revisitWarnaSisa,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
