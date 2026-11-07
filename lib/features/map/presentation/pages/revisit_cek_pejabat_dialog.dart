import 'package:flutter/material.dart';

import '../../data/models/revisit_models.dart';
import '../../data/services/revisit_laporan_docx.dart';
import '../../data/services/revisit_service.dart';
import 'revisit_laporan_edit_dialog.dart';
import 'revisit_page.dart';

/// Satu halaman laporan (petugas + hari ke-) yang pejabat yang ditemui-nya
/// belum lengkap. Sama seperti dokumen, satu halaman cukup diisi di salah
/// satu SLS-nya; [laporan] = SLS yang pejabatnya tercetak (atau SLS pertama
/// bila belum ada), yaitu yang diedit untuk melengkapinya.
class RevisitPejabatKurang {
  final RevisitLaporanHalaman halaman;
  final RevisitLaporan laporan;
  final bool namaKosong;
  final bool jabatanKosong;

  const RevisitPejabatKurang(
    this.halaman,
    this.laporan, {
    required this.namaKosong,
    required this.jabatanKosong,
  });

  String get keterangan => namaKosong && jabatanKosong
      ? 'Nama & jabatan pejabat kosong'
      : namaKosong
      ? 'Nama pejabat kosong'
      : 'Jabatan pejabat kosong';
}

/// Halaman laporan (dikelompokkan seperti dokumen) yang nama dan/atau
/// jabatan pejabatnya kosong menurut [pejabat] (per id laporan), urut nama
/// petugas lalu hari ke-.
List<RevisitPejabatKurang> revisitPejabatKurang(
  List<RevisitLaporan> laporan,
  Map<String, RevisitPejabat> pejabat,
) {
  final hasil = <RevisitPejabatKurang>[];
  for (final h in RevisitLaporanDocx.kelompokkan(laporan)) {
    // Sama dengan RevisitLaporanDocx.pejabatHalaman: isian pertama yang ada.
    final sumber = h.laporan.firstWhere(
      (l) => !(pejabat[l.id]?.kosong ?? true),
      orElse: () => h.laporan.first,
    );
    final p = pejabat[sumber.id];
    final namaKosong = (p?.nama ?? '').trim().isEmpty;
    final jabatanKosong = (p?.jabatan ?? '').trim().isEmpty;
    if (namaKosong || jabatanKosong) {
      hasil.add(
        RevisitPejabatKurang(
          h,
          sumber,
          namaKosong: namaKosong,
          jabatanKosong: jabatanKosong,
        ),
      );
    }
  }
  hasil.sort((a, b) {
    final n = a.halaman.petugasNama.toLowerCase().compareTo(
      b.halaman.petugasNama.toLowerCase(),
    );
    if (n != 0) return n;
    final h = a.halaman.hariKe.compareTo(b.halaman.hariKe);
    if (h != 0) return h;
    return a.halaman.tanggal.compareTo(b.halaman.tanggal);
  });
  return hasil;
}

/// Jumlah halaman laporan (petugas + hari ke-) dari [laporan].
int revisitJumlahHalaman(List<RevisitLaporan> laporan) =>
    RevisitLaporanDocx.kelompokkan(laporan).length;

/// Ambil pejabat untuk [laporan] lalu kembalikan yang belum lengkap.
Future<List<RevisitPejabatKurang>> revisitCekPejabat(
  List<RevisitLaporan> laporan,
) async {
  final pejabat = await RevisitService().fetchPejabat(
    laporan.map((l) => l.id).toList(),
  );
  return revisitPejabatKurang(laporan, pejabat);
}

/// Admin: daftar laporan yang pejabat yang ditemui-nya belum lengkap; tiap
/// baris bisa langsung diedit. Isi daftar dimuat ulang setelah edit.
Future<void> showRevisitCekPejabatDialog(
  BuildContext context,
  List<RevisitLaporan> laporan,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RevisitCekPejabatDialog(laporan: laporan),
  );
}

class _RevisitCekPejabatDialog extends StatefulWidget {
  final List<RevisitLaporan> laporan;

  const _RevisitCekPejabatDialog({required this.laporan});

  @override
  State<_RevisitCekPejabatDialog> createState() =>
      _RevisitCekPejabatDialogState();
}

class _RevisitCekPejabatDialogState extends State<_RevisitCekPejabatDialog> {
  late Future<List<RevisitPejabatKurang>> _kurang = revisitCekPejabat(
    widget.laporan,
  );
  late final int _halaman = revisitJumlahHalaman(widget.laporan);

  Future<void> _edit(RevisitLaporan l) async {
    final ok = await showRevisitLaporanEditDialog(context, l);
    if (ok && mounted) {
      setState(() => _kurang = revisitCekPejabat(widget.laporan));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cek pejabat yang ditemui'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: FutureBuilder<List<RevisitPejabatKurang>>(
          future: _kurang,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                child: Text(
                  'Gagal memeriksa pejabat: ${snap.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }
            final kurang = snap.data!;
            if (kurang.isEmpty) {
              return Center(
                child: Text(
                  'Semua $_halaman halaman laporan sudah berisi nama & '
                  'jabatan pejabat.',
                  textAlign: TextAlign.center,
                ),
              );
            }
            final petugas = kurang.map((k) => k.laporan.petugasId).toSet();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${kurang.length} dari $_halaman halaman laporan '
                  '(${petugas.length} petugas) belum lengkap. Cukup diisi '
                  'di salah satu SLS pada hari itu.',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB45309),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: kurang.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final k = kurang[i];
                      final l = k.laporan;
                      final sls = k.halaman.laporan.length;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          l.petugasNama.isEmpty ? '-' : l.petugasNama,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            k.halaman.hariKe > 0
                                ? 'Hari ke-${k.halaman.hariKe}'
                                : revisitDateLabel(k.halaman.tanggal),
                            sls > 1 ? '$sls SLS' : l.slsLabel,
                            k.keterangan,
                          ].join(' · '),
                        ),
                        trailing: IconButton(
                          tooltip: 'Isi pejabat',
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: revisitPrimary,
                          ),
                          onPressed: () => _edit(l),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}
