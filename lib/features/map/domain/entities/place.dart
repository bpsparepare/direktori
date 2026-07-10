import 'package:latlong2/latlong.dart';

class Place {
  final String id;
  final String name;
  final String description;
  final LatLng position;
  final int? noBang;
  final String? urlGambar;
  final String? gcsResult;
  final String? address;
  final String? statusPerusahaan;

  const Place({
    required this.id,
    required this.name,
    required this.description,
    required this.position,
    this.noBang,
    this.urlGambar,
    this.gcsResult,
    this.address,
    this.statusPerusahaan,
  });

  Place copyWith({
    String? id,
    String? name,
    String? description,
    LatLng? position,
    int? noBang,
    String? urlGambar,
    String? gcsResult,
    String? address,
    String? statusPerusahaan,
  }) {
    return Place(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      position: position ?? this.position,
      noBang: noBang ?? this.noBang,
      urlGambar: urlGambar ?? this.urlGambar,
      gcsResult: gcsResult ?? this.gcsResult,
      address: address ?? this.address,
      statusPerusahaan: statusPerusahaan ?? this.statusPerusahaan,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'lat': position.latitude,
      'lng': position.longitude,
      'noBang': noBang,
      'urlGambar': urlGambar,
      'gcsResult': gcsResult,
      'address': address,
      'statusPerusahaan': statusPerusahaan,
    };
  }

  factory Place.fromJson(Map<String, dynamic> json) {
    final rawNoBang = json['noBang'];
    return Place(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      position: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      ),
      noBang: rawNoBang is int
          ? rawNoBang
          : rawNoBang is num
          ? rawNoBang.toInt()
          : int.tryParse(rawNoBang?.toString() ?? ''),
      urlGambar: json['urlGambar'] as String?,
      gcsResult: json['gcsResult'] as String?,
      address: json['address'] as String?,
      statusPerusahaan: json['statusPerusahaan'] as String?,
    );
  }
}
