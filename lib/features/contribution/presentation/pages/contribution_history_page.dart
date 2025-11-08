import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/contribution_bloc.dart';
import '../bloc/contribution_event.dart';
import '../widgets/contribution_list_widget.dart';

class ContributionHistoryPage extends StatelessWidget {
  const ContributionHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Kontribusi')),
      body: RefreshIndicator(
        onRefresh: () async {
          context.read<ContributionBloc>().add(
            const GetUserContributionsEvent(),
          );
        },
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: ContributionListWidget(),
        ),
      ),
    );
  }
}
