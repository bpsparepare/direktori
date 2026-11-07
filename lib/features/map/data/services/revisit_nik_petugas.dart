import 'package:flutter/foundation.dart' show visibleForTesting;

// NIK petugas revisit untuk kolom "NIP Lama Peserta" di Excel translok.
// Data petugas di aplikasi belum menyimpan NIK, jadi dicocokkan lewat nama
// (lihat normalisasiNama). Datanya pribadi, jadi tidak disimpan di kode
// maupun repo: dibaca dari env (lihat daftarNikPetugas).

/// Daftar mentah dari dart-define `REVISIT_NIK_PETUGAS` (di
/// env/env.local.json, tidak ikut ke repo): "Nama|NIK;Nama|NIK;…".
const String _nikDariEnv = String.fromEnvironment('REVISIT_NIK_PETUGAS');

/// Urai "Nama|NIK;Nama|NIK" jadi pasangan (nama, nik). Entri rusak dilewati.
List<(String nama, String nik)> uraiNikPetugas(String mentah) => [
  for (final entri in mentah.split(';'))
    if (entri.split('|') case [
      final nama,
      final nik,
    ] when nama.trim().isNotEmpty && nik.trim().isNotEmpty)
      (nama.trim(), nik.trim()),
];

List<(String nama, String nik)> _daftar = uraiNikPetugas(_nikDariEnv);
Map<String, String> _perNama = _petakan(_daftar);

Map<String, String> _petakan(List<(String, String)> daftar) => {
  for (final (nama, nik) in daftar) normalisasiNama(nama): nik,
};

/// Pasangan (nama, nik) petugas revisit, urut seperti di env.
List<(String nama, String nik)> get daftarNikPetugas => _daftar;

/// [daftarNikPetugas] dengan kunci nama yang sudah dinormalisasi.
Map<String, String> get nikPetugasRevisit => _perNama;

/// Ganti daftar NIK (untuk tes, tanpa data asli).
@visibleForTesting
void aturNikPetugas(List<(String nama, String nik)> daftar) {
  _daftar = daftar;
  _perNama = _petakan(daftar);
}

/// Bentuk baku nama untuk pencocokan: huruf kecil, gelar setelah koma
/// dibuang, tanda baca jadi spasi, spasi ganda dirapatkan.
String normalisasiNama(String nama) => nama
    .split(',')
    .first
    .toLowerCase()
    .replaceAll(RegExp('[^a-z ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// NIK untuk [nama] petugas, atau '' bila belum terdaftar.
String nikPetugas(String nama) =>
    nikPetugasRevisit[normalisasiNama(nama)] ?? '';
