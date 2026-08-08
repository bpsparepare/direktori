import 'package:latlong2/latlong.dart';

class PolygonData {
  final List<LatLng> points;
  final String? name; // nmsls
  final String? kecamatan; // nmkec
  final String? desa; // nmdesa
  final String? idsls; // idsls for sorting
  final String? idsubsls; // idsubsls for assignment matching
  final String? subsls; // suffix subsls for display
  final String? kodePos; // kode_pos from GeoJSON
  final String? namaPetugas; // nama PPL (pendata) untuk polygon assignment
  final String? namaPengawas; // nama PML (pengawas) untuk polygon assignment
  final String?
  statusPendataan; // kode status pendataan (BELUM/P30/.../SELESAI)

  const PolygonData({
    required this.points,
    this.name,
    this.kecamatan,
    this.desa,
    this.idsls,
    this.idsubsls,
    this.subsls,
    this.kodePos,
    this.namaPetugas,
    this.namaPengawas,
    this.statusPendataan,
  });

  PolygonData copyWith({
    List<LatLng>? points,
    String? name,
    String? kecamatan,
    String? desa,
    String? idsls,
    String? idsubsls,
    String? subsls,
    String? kodePos,
    String? namaPetugas,
    String? namaPengawas,
    String? statusPendataan,
  }) {
    return PolygonData(
      points: points ?? this.points,
      name: name ?? this.name,
      kecamatan: kecamatan ?? this.kecamatan,
      desa: desa ?? this.desa,
      idsls: idsls ?? this.idsls,
      idsubsls: idsubsls ?? this.idsubsls,
      subsls: subsls ?? this.subsls,
      kodePos: kodePos ?? this.kodePos,
      namaPetugas: namaPetugas ?? this.namaPetugas,
      namaPengawas: namaPengawas ?? this.namaPengawas,
      statusPendataan: statusPendataan ?? this.statusPendataan,
    );
  }
}
