import 'package:latlong2/latlong.dart';
import '../../../map/domain/entities/place.dart';

class ScrapedPlace {
  final String link;
  final String title;
  final String? category;
  final String? alamat;
  final String? address;
  final String? website;
  final String? phone;
  final int? reviewCount;
  final double? reviewRating;
  final Map<String, int>? reviewsPerRating;
  final double latitude;
  final double longitude;
  final String? cid;
  final String? thumbnail;
  final String? status;

  const ScrapedPlace({
    required this.link,
    required this.title,
    required this.latitude,
    required this.longitude,
    this.category,
    this.alamat,
    this.address,
    this.website,
    this.phone,
    this.reviewCount,
    this.reviewRating,
    this.reviewsPerRating,
    this.cid,
    this.thumbnail,
    this.status,
  });

  factory ScrapedPlace.fromRow(Map<String, dynamic> row) {
    double parseDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    int? parseInt(dynamic v) {
      if (v == null || (v is String && v.trim().isEmpty)) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    // Parse reviews_per_rating as map like "{1: 2, 2: 0, 3: 1, 4: 5, 5: 10}" or "1:2|2:0|..."
    Map<String, int>? parseReviews(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      final Map<String, int> m = {};
      // Try pipe-delimited
      if (s.contains('|')) {
        for (final part in s.split('|')) {
          final kv = part.split(':');
          if (kv.length == 2) {
            final key = kv[0].trim();
            final val = int.tryParse(kv[1].trim()) ?? 0;
            m[key] = val;
          }
        }
        return m.isEmpty ? null : m;
      }
      // Try JSON-ish
      final cleaned = s.replaceAll(RegExp(r'[{}]'), '');
      for (final part in cleaned.split(',')) {
        final kv = part.split(':');
        if (kv.length == 2) {
          final key = kv[0].trim();
          final val = int.tryParse(kv[1].trim()) ?? 0;
          m[key] = val;
        }
      }
      return m.isEmpty ? null : m;
    }

    return ScrapedPlace(
      link: (row['link'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      category: row['category']?.toString(),
      alamat: row['alamat']?.toString(),
      address: row['address']?.toString(),
      website: row['website']?.toString(),
      phone: row['phone']?.toString(),
      reviewCount: parseInt(row['review_count']),
      reviewRating: row['review_rating'] == null
          ? null
          : parseDouble(row['review_rating']),
      reviewsPerRating: parseReviews(row['reviews_per_rating']),
      latitude: parseDouble(row['latitude']),
      longitude: parseDouble(row['longitude']),
      cid: row['cid']?.toString(),
      thumbnail: row['thumbnail']?.toString(),
      status: row['status']?.toString(),
    );
  }

  Place toPlace() {
    final idBase = cid?.isNotEmpty == true
        ? cid!
        : '$latitude,$longitude,$title';
    final id = 'scrape:$idBase';
    final descParts = <String>[
      if (category?.isNotEmpty == true) 'Kategori: $category',
      if (address?.isNotEmpty == true)
        'Alamat: $address'
      else if (alamat?.isNotEmpty == true)
        'Alamat: $alamat',
      if (website?.isNotEmpty == true) 'Web: $website',
      if (phone?.isNotEmpty == true) 'Telp: $phone',
      if (reviewRating != null) 'Rating: ${reviewRating!.toStringAsFixed(1)}',
      if (reviewCount != null) 'Ulasan: $reviewCount',
      if (status?.isNotEmpty == true) 'Status: $status',
    ];
    return Place(
      id: id,
      name: title,
      description: descParts.join(' | '),
      position: LatLng(latitude, longitude),
      urlGambar: thumbnail,
    );
  }
}
