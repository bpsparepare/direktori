import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:developer' as developer;
import '../bloc/auth_bloc.dart';
import '../pages/login_page.dart';
import '../../../map/presentation/pages/main_page.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        developer.log(
          '🔄 AuthWrapper: Current state: ${state.runtimeType}',
          name: 'AuthWrapper',
        );

        if (state is AuthLoading || state is AuthInitial) {
          developer.log(
            '⏳ AuthWrapper: Showing loading screen',
            name: 'AuthWrapper',
          );
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state is AuthAuthenticated) {
          developer.log(
            '✅ AuthWrapper: User authenticated, navigating to MainPage',
            name: 'AuthWrapper',
          );
          developer.log(
            '✅ AuthWrapper: User email: ${state.user.email}',
            name: 'AuthWrapper',
          );
          return const MainPage();
        }

        if (state is AuthError) {
          developer.log(
            '❌ AuthWrapper: Auth error: ${state.message}',
            name: 'AuthWrapper',
          );
        }

        developer.log('🔄 AuthWrapper: Showing LoginPage', name: 'AuthWrapper');
        return const LoginPage();
      },
    );
  }
}