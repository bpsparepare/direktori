import 'package:latlong2/latlong.dart';

class Place {
  final String id;
  final String name;
  final String description;
  final LatLng position;
  final String? urlGambar;
  final String? gcsResult;
  final String? address;
  final String? statusPerusahaan;

  const Place({
    required this.id,
    required this.name,
    required this.description,
    required this.position,
    this.urlGambar,
    this.gcsResult,
    this.address,
    this.statusPerusahaan,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'lat': position.latitude,
      'lng': position.longitude,
      'urlGambar': urlGambar,
      'gcsResult': gcsResult,
      'address': address,
      'statusPerusahaan': statusPerusahaan,
    };
  }

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      position: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      ),
      urlGambar: json['urlGambar'] as String?,
      gcsResult: json['gcsResult'] as String?,
      address: json['address'] as String?,
      statusPerusahaan: json['statusPerusahaan'] as String?,
    );
  }
}
