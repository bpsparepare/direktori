import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/contribution_bloc.dart';
import '../bloc/contribution_event.dart';
import '../widgets/leaderboard_widget.dart';

class LeaderboardPage extends StatelessWidget {
  const LeaderboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard Kontributor')),
      body: RefreshIndicator(
        onRefresh: () async {
          context.read<ContributionBloc>().add(const GetLeaderboardEvent());
        },
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: LeaderboardWidget(),
        ),
      ),
    );
  }
}
