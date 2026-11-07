import 'package:flutter_test/flutter_test.dart';
import 'package:direktori/features/map/data/models/revisit_models.dart';
import 'package:direktori/features/map/presentation/pages/revisit_cek_pejabat_dialog.dart';

RevisitLaporan _laporan(
  String id,
  String petugas,
  int hariKe, {
  String kodeSls = '7372010001001001',
}) {
  return RevisitLaporan.fromJson({
    'id': id,
    'kode_sls': kodeSls,
    'nm_kec': 'Bacukiki Barat',
    'nm_desa': 'Lumpue',
    'nm_sls': 'RT 01',
    'petugas_id': 'p-$petugas',
    'petugas_nama': petugas,
    'petugas_role': 'PPL',
    'petugas_tim': 'Tim A',
    'hari_ke': hariKe,
    'tanggal': DateTime(2026, 9, 17).toIso8601String(),
    'status': 'selesai',
    'jumlah_dicek': 1,
    'jumlah_submit': 1,
    'jumlah_belum_didata': 0,
    'catatan': 'ok',
    'foto': const [],
  });
}

void main() {
  test('hanya laporan dengan nama/jabatan kosong, urut petugas & hari', () {
    final laporan = [
      _laporan('lengkap', 'Andi', 1),
      _laporan('tanpa-jabatan', 'Citra', 2),
      _laporan('tanpa-data', 'Budi', 3),
      _laporan('spasi', 'Budi', 1),
    ];
    final pejabat = {
      'lengkap': const RevisitPejabat(nama: 'Pak RT', jabatan: 'Ketua RT'),
      'tanpa-jabatan': const RevisitPejabat(nama: 'Bu Lurah', jabatan: ''),
      'spasi': const RevisitPejabat(nama: '  ', jabatan: 'Ketua RW'),
    };

    final kurang = revisitPejabatKurang(laporan, pejabat);

    expect(kurang.map((k) => k.laporan.id), [
      'spasi',
      'tanpa-data',
      'tanpa-jabatan',
    ]);
    expect(kurang[0].keterangan, 'Nama pejabat kosong');
    expect(kurang[1].keterangan, 'Nama & jabatan pejabat kosong');
    expect(kurang[2].keterangan, 'Jabatan pejabat kosong');
  });

  test('satu halaman cukup diisi di salah satu SLS-nya', () {
    // Budi hari 1 punya dua SLS; pejabat diisi di SLS kedua saja.
    final laporan = [
      _laporan('sls1', 'Budi', 1, kodeSls: '7372010001001001'),
      _laporan('sls2', 'Budi', 1, kodeSls: '7372010001001002'),
      _laporan('hari2', 'Budi', 2),
    ];
    final pejabat = {
      'sls2': const RevisitPejabat(nama: 'Pak RT', jabatan: 'Ketua RT'),
    };

    final kurang = revisitPejabatKurang(laporan, pejabat);

    expect(kurang.map((k) => k.laporan.id), ['hari2']);
    expect(revisitJumlahHalaman(laporan), 2);
  });

  test('isian setengah: yang diedit adalah SLS yang tercetak', () {
    final laporan = [
      _laporan('sls1', 'Budi', 1, kodeSls: '7372010001001001'),
      _laporan('sls2', 'Budi', 1, kodeSls: '7372010001001002'),
    ];
    final kurang = revisitPejabatKurang(laporan, {
      'sls2': const RevisitPejabat(nama: 'Pak RT', jabatan: ''),
    });
    expect(kurang.single.laporan.id, 'sls2');
    expect(kurang.single.keterangan, 'Jabatan pejabat kosong');
  });

  test('semua lengkap → kosong', () {
    final kurang = revisitPejabatKurang(
      [_laporan('a', 'Andi', 1)],
      {'a': const RevisitPejabat(nama: 'X', jabatan: 'Y')},
    );
    expect(kurang, isEmpty);
  });
}
