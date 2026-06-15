class AssignmentPlaceRecord {
  final String assignmentId;
  final int? noBang;
  final String namaUsaha;
  final double latitude;
  final double longitude;

  const AssignmentPlaceRecord({
    required this.assignmentId,
    required this.noBang,
    required this.namaUsaha,
    required this.latitude,
    required this.longitude,
  });

  factory AssignmentPlaceRecord.fromJson(Map<String, dynamic> json) {
    double toDoubleValue(dynamic value) {
      if (value is num) return value.toDouble();
      return double.parse(value.toString());
    }

    int? toIntValue(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    return AssignmentPlaceRecord(
      assignmentId: json['assignment_id']?.toString() ?? '',
      noBang: toIntValue(json['no_bang']),
      namaUsaha: json['nama_usaha']?.toString() ?? '',
      latitude: toDoubleValue(json['latitude']),
      longitude: toDoubleValue(json['longitude']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'assignment_id': assignmentId,
      'no_bang': noBang,
      'nama_usaha': namaUsaha,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}
