class AssignmentPlaceRecord {
  final String id;
  final String workspaceKeyHash;
  final String surveyPeriodId;
  final String assignmentId;
  final String idsbr;
  final String namaUsaha;
  final String alamat;
  final String kodeUsaha;
  final String statusText;
  final double latitude;
  final double longitude;
  final String? modified;
  final String? sourceModifiedAt;
  final String? lastSeenAt;
  final String? updatedAt;
  final String fullcodeSubsls;

  const AssignmentPlaceRecord({
    required this.id,
    required this.workspaceKeyHash,
    required this.surveyPeriodId,
    required this.assignmentId,
    required this.idsbr,
    required this.namaUsaha,
    required this.alamat,
    required this.kodeUsaha,
    required this.statusText,
    required this.latitude,
    required this.longitude,
    required this.modified,
    required this.sourceModifiedAt,
    required this.lastSeenAt,
    required this.updatedAt,
    required this.fullcodeSubsls,
  });

  factory AssignmentPlaceRecord.fromJson(Map<String, dynamic> json) {
    double toDoubleValue(dynamic value) {
      if (value is num) return value.toDouble();
      return double.parse(value.toString());
    }

    return AssignmentPlaceRecord(
      id: json['id']?.toString() ?? '',
      workspaceKeyHash: json['workspace_key_hash']?.toString() ?? '',
      surveyPeriodId: json['survey_period_id']?.toString() ?? '',
      assignmentId: json['assignment_id']?.toString() ?? '',
      idsbr: json['idsbr']?.toString() ?? '',
      namaUsaha: json['nama_usaha']?.toString() ?? '',
      alamat: json['alamat']?.toString() ?? '',
      kodeUsaha: json['kode_usaha']?.toString() ?? '',
      statusText: json['status_text']?.toString() ?? '',
      latitude: toDoubleValue(json['latitude']),
      longitude: toDoubleValue(json['longitude']),
      modified: json['modified']?.toString(),
      sourceModifiedAt: json['source_modified_at']?.toString(),
      lastSeenAt: json['last_seen_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
      fullcodeSubsls: json['fullcode_subsls']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'workspace_key_hash': workspaceKeyHash,
      'survey_period_id': surveyPeriodId,
      'assignment_id': assignmentId,
      'idsbr': idsbr,
      'nama_usaha': namaUsaha,
      'alamat': alamat,
      'kode_usaha': kodeUsaha,
      'status_text': statusText,
      'latitude': latitude,
      'longitude': longitude,
      'modified': modified,
      'source_modified_at': sourceModifiedAt,
      'last_seen_at': lastSeenAt,
      'updated_at': updatedAt,
      'fullcode_subsls': fullcodeSubsls,
    };
  }
}
