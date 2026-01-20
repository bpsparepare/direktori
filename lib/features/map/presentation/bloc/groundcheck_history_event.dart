import 'package:equatable/equatable.dart';

abstract class GroundcheckHistoryEvent extends Equatable {
  const GroundcheckHistoryEvent();

  @override
  List<Object?> get props => [];
}

class LoadGroundcheckHistory extends GroundcheckHistoryEvent {
  final String? userId;

  const LoadGroundcheckHistory({this.userId});

  @override
  List<Object?> get props => [userId];
}

class LoadGroundcheckLeaderboard extends GroundcheckHistoryEvent {}
