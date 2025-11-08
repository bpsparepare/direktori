import '../../domain/entities/user_contribution.dart';

/// Model untuk UserContribution yang menangani serialisasi JSON
class UserContributionModel extends UserContribution {
  const UserContributionModel({
    required super.id,
    required super.userId,
    required super.actionType,
    required super.targetType,
    required super.targetId,
    super.changes,
    required super.points,
    required super.status,
    super.latitude,
    super.longitude,
    required super.createdAt,
    required super.updatedAt,
  });

  /// Factory constructor dari JSON
  factory UserContributionModel.fromJson(Map<String, dynamic> json) {
    // Denormalisasi agar nilai yang dibaca dari DB konsisten dengan label UI
    final dbActionType = (json['action_type'] as String?) ?? '';
    final dbTargetType = (json['target_type'] as String?) ?? '';
    // Prefer target_uuid (uuid) jika tersedia, fallback ke target_id (bigint)
    final rawTargetUuid = json['target_uuid'];
    final rawTargetId = json['target_id'];
    final parsedTargetIdString = rawTargetUuid != null
        ? rawTargetUuid.toString()
        : (rawTargetId != null ? rawTargetId.toString() : '');

    return UserContributionModel(
      // id di DB bertipe BIGSERIAL (integer), konversi ke String
      id: json['id']?.toString() ?? '',
      userId: json['user_id'] as String,
      actionType: _denormalizeActionType(dbActionType),
      targetType: _denormalizeTargetType(dbTargetType),
      // Gunakan target_uuid (uuid) bila ada; jika tidak, gunakan target_id (bigint)
      targetId: parsedTargetIdString,
      changes: json['changes'] as Map<String, dynamic>?,
      points: json['points_earned'] as int,
      status: json['status'] as String,
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert ke JSON
  Map<String, dynamic> toJson() {
    // Normalisasi nilai agar sesuai dengan schema database
    final normalizedActionType = _normalizeActionType(actionType);
    final normalizedTargetType = _normalizeTargetType(targetType);
    final parsedTargetId = _parseTargetId(targetId);
    final parsedTargetUuid = _parseTargetUuid(targetId);

    final Map<String, dynamic> data = {
      // Jangan kirim 'id' jika kosong; biarkan DB generate (BIGSERIAL)
      'user_id': userId,
      'action_type': normalizedActionType,
      'target_type': normalizedTargetType,
      // Kirim kedua kolom: target_uuid (uuid) bila format UUID, target_id (bigint) bila angka
      'target_uuid': parsedTargetUuid,
      'target_id': parsedTargetId,
      'changes': changes,
      'points_earned': points,
      'status': status,
      'latitude': latitude,
      'longitude': longitude,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };

    // Sertakan 'id' hanya jika tidak kosong
    if (id.isNotEmpty) {
      data['id'] = id;
    }

    return data;
  }

  /// Factory constructor dari Entity
  factory UserContributionModel.fromEntity(UserContribution entity) {
    return UserContributionModel(
      id: entity.id,
      userId: entity.userId,
      actionType: entity.actionType,
      targetType: entity.targetType,
      targetId: entity.targetId,
      changes: entity.changes,
      points: entity.points,
      status: entity.status,
      latitude: entity.latitude,
      longitude: entity.longitude,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }

  /// Convert ke Entity
  UserContribution toEntity() {
    return UserContribution(
      id: id,
      userId: userId,
      actionType: actionType,
      targetType: targetType,
      targetId: targetId,
      changes: changes,
      points: points,
      status: status,
      latitude: latitude,
      longitude: longitude,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Copy with method untuk model
  UserContributionModel copyWithModel({
    String? id,
    String? userId,
    String? actionType,
    String? targetType,
    String? targetId,
    Map<String, dynamic>? changes,
    int? points,
    String? status,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserContributionModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      actionType: actionType ?? this.actionType,
      targetType: targetType ?? this.targetType,
      targetId: targetId ?? this.targetId,
      changes: changes ?? this.changes,
      points: points ?? this.points,
      status: status ?? this.status,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Helper: normalisasi action type agar sesuai CHECK constraint DB
  static String _normalizeActionType(String actionType) {
    switch (actionType) {
      case 'create':
        return 'add';
      case 'update':
        return 'edit';
      case 'verify':
        // Tidak ada nilai 'verify' di DB, gunakan 'edit' sebagai representasi
        return 'edit';
      case 'add_location':
        return 'add';
      case 'edit_location':
        return 'edit';
      case 'delete_location':
        return 'delete';
      // Pemetaan actionType baru ke nilai yang diizinkan DB
      case 'set_first_coordinates':
      case 'update_coordinates_major':
      case 'update_coordinates_minor':
        return 'edit';
      case 'confirm_closed':
      case 'confirm_not_found':
      case 'confirm_open':
      case 'confirm_uncertain':
        return 'edit';
      case 'add_directory_manual':
      case 'add_directory_scrape':
        return 'add';
      case 'scrape_update_status':
        return 'edit';
      case 'add_kbli':
      case 'update_kbli':
      case 'add_description':
      case 'update_description':
      case 'add_address':
      case 'update_address':
      case 'add_photo':
      case 'update_photo':
        return 'edit';
      case 'add':
      case 'edit':
      case 'delete':
        return actionType;
      default:
        return actionType; // fallback: kirim apa adanya
    }
  }

  // Helper: normalisasi target type agar sesuai CHECK constraint DB
  static String _normalizeTargetType(String targetType) {
    switch (targetType) {
      case 'directory':
        return 'direktori';
      case 'business':
        return 'direktori';
      case 'location':
        return 'wilayah';
      default:
        return targetType;
    }
  }

  // Helper: parse target_id ke int (BIGINT), atau null jika bukan angka
  static int? _parseTargetId(String targetId) {
    if (targetId.isEmpty) return null;
    return int.tryParse(targetId);
  }

  // Helper: parse target_uuid bila string tampak seperti UUID v4
  static String? _parseTargetUuid(String targetId) {
    if (targetId.isEmpty) return null;
    // Sederhana: jika mengandung 4 tanda '-' dan panjang tipikal 36, asumsikan UUID
    final isLikelyUuid = targetId.length == 36 && targetId.split('-').length == 5;
    return isLikelyUuid ? targetId : null;
  }

  // Helper: denormalisasi action type dari DB ke label UI
  static String _denormalizeActionType(String dbActionType) {
    switch (dbActionType) {
      case 'add':
        return 'create';
      case 'edit':
        return 'update';
      case 'delete':
        return 'delete';
      default:
        return dbActionType;
    }
  }

  // Helper: denormalisasi target type dari DB ke label UI
  static String _denormalizeTargetType(String dbTargetType) {
    switch (dbTargetType) {
      case 'direktori':
        return 'direktori';
      case 'wilayah':
        return 'location';
      default:
        return dbTargetType;
    }
  }
}
