import 'package:equatable/equatable.dart';

class Direktori extends Equatable {
  final String id;
  final String idSbr;
  final String namaUsaha;
  final String? alamat;
  final String idSls;
  final List<Map<String, dynamic>> kegiatanUsaha;
  final String? skalaUsaha;
  final String? keterangan;
  final String? nib;
  final double? lat;
  final double? long;
  final String? urlGambar;
  final String? kodePos;
  final String? jenisPerusahaan;
  final String? pemilik;
  final String? nikPemilik;
  final String? nohpPemilik;
  final int? tenagaKerja;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? namaKomersialUsaha;
  final String? nomorTelepon;
  final String? nomorWhatsapp;
  final String? email;
  final String? website;
  final String? sumberData;
  final double? latitude;
  final double? longitude;
  final int? keberadaanUsaha;
  final int? jenisKepemilikanUsaha;
  final int? bentukBadanHukumUsaha;
  final String? deskripsiBadanUsahaLainnya;
  final int? tahunBerdiri;
  final int? jaringanUsaha;
  final int? sektorInstitusi;
  final String? nmProv;
  final String? nmKab;
  final String? kbli;
  final List<String>? tag;

  const Direktori({
    required this.id,
    required this.idSbr,
    required this.namaUsaha,
    this.alamat,
    required this.idSls,
    required this.kegiatanUsaha,
    this.skalaUsaha,
    this.keterangan,
    this.nib,
    this.lat,
    this.long,
    this.urlGambar,
    this.kodePos,
    this.jenisPerusahaan,
    this.pemilik,
    this.nikPemilik,
    this.nohpPemilik,
    this.tenagaKerja,
    this.createdAt,
    this.updatedAt,
    this.namaKomersialUsaha,
    this.nomorTelepon,
    this.nomorWhatsapp,
    this.email,
    this.website,
    this.sumberData,
    this.latitude,
    this.longitude,
    this.keberadaanUsaha,
    this.jenisKepemilikanUsaha,
    this.bentukBadanHukumUsaha,
    this.deskripsiBadanUsahaLainnya,
    this.tahunBerdiri,
    this.jaringanUsaha,
    this.sektorInstitusi,
    this.nmProv,
    this.nmKab,
    this.kbli,
    this.tag,
  });

  @override
  List<Object?> get props => [
    id,
    idSbr,
    namaUsaha,
    alamat,
    idSls,
    kegiatanUsaha,
    skalaUsaha,
    keterangan,
    nib,
    lat,
    long,
    urlGambar,
    kodePos,
    jenisPerusahaan,
    pemilik,
    nikPemilik,
    nohpPemilik,
    tenagaKerja,
    createdAt,
    updatedAt,
    namaKomersialUsaha,
    nomorTelepon,
    nomorWhatsapp,
    email,
    website,
    sumberData,
    latitude,
    longitude,
    keberadaanUsaha,
    jenisKepemilikanUsaha,
    bentukBadanHukumUsaha,
    deskripsiBadanUsahaLainnya,
    tahunBerdiri,
    jaringanUsaha,
    sektorInstitusi,
    nmProv,
    nmKab,
    kbli,
  ];
}
