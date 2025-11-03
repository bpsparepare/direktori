import 'package:equatable/equatable.dart';

/// Entity yang merepresentasikan kontribusi pengguna
class UserContribution extends Equatable {
  final String id;
  final String userId;
  final String actionType;
  final String targetType;
  final String targetId;
  final Map<String, dynamic>? changes;
  final int points;
  final String status;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserContribution({
    required this.id,
    required this.userId,
    required this.actionType,
    required this.targetType,
    required this.targetId,
    this.changes,
    required this.points,
    required this.status,
    this.latitude,
    this.longitude,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
        id,
        userId,
        actionType,
        targetType,
        targetId,
        changes,
        points,
        status,
        latitude,
        longitude,
        createdAt,
        updatedAt,
      ];

  UserContribution copyWith({
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
    return UserContribution(
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
}

/// Enum untuk jenis aksi kontribusi
enum ContributionActionType {
  create('create'),
  edit('edit'),
  verify('verify'),
  report('report'),
  delete('delete');

  const ContributionActionType(this.value);
  final String value;
}

/// Enum untuk target kontribusi
enum ContributionTargetType {
  directory('directory'),
  location('location'),
  business('business');

  const ContributionTargetType(this.value);
  final String value;
}

/// Enum untuk status kontribusi
enum ContributionStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected'),
  processing('processing');

  const ContributionStatus(this.value);
  final String value;
}