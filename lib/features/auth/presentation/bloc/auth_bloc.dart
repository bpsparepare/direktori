import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'dart:developer' as developer;
import '../../domain/entities/user_entity.dart';
import '../../domain/usecases/get_current_user_usecase.dart';
import '../../domain/usecases/sign_in_with_email_usecase.dart';
import '../../domain/usecases/sign_in_with_google_usecase.dart';
import '../../domain/usecases/sign_out_usecase.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final GetCurrentUserUseCase getCurrentUserUseCase;
  final SignInWithEmailUseCase signInWithEmailUseCase;
  final SignInWithGoogleUseCase signInWithGoogleUseCase;
  final SignOutUseCase signOutUseCase;

  late StreamSubscription<UserEntity?> _authStateSubscription;

  AuthBloc({
    required this.getCurrentUserUseCase,
    required this.signInWithEmailUseCase,
    required this.signInWithGoogleUseCase,
    required this.signOutUseCase,
  }) : super(AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthSignInWithEmailRequested>(_onSignInWithEmailRequested);
    on<AuthSignInWithGoogleRequested>(_onSignInWithGoogleRequested);
    on<AuthSignOutRequested>(_onSignOutRequested);
    on<AuthUserChanged>(_onAuthUserChanged);

    // Listen to auth state changes
    _authStateSubscription = getCurrentUserUseCase.authStateChanges.listen(
      (user) => add(AuthUserChanged(user)),
    );
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final user = await getCurrentUserUseCase();
      if (user != null) {
        emit(AuthAuthenticated(user));
      } else {
        emit(AuthUnauthenticated());
      }
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onSignInWithEmailRequested(
    AuthSignInWithEmailRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final user = await signInWithEmailUseCase(event.email, event.password);
      emit(AuthAuthenticated(user));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onSignInWithGoogleRequested(
    AuthSignInWithGoogleRequested event,
    Emitter<AuthState> emit,
  ) async {
    developer.log('🔄 AuthBloc: Google Sign-In requested', name: 'AuthBloc');
    emit(AuthLoading());
    try {
      developer.log(
        '🔄 AuthBloc: Calling signInWithGoogleUseCase',
        name: 'AuthBloc',
      );
      final user = await signInWithGoogleUseCase();
      developer.log(
        '✅ AuthBloc: Google Sign-In successful, user: ${user.email}',
        name: 'AuthBloc',
      );
      developer.log(
        '🔄 AuthBloc: Emitting AuthAuthenticated state',
        name: 'AuthBloc',
      );
      emit(AuthAuthenticated(user));
      developer.log(
        '✅ AuthBloc: AuthAuthenticated state emitted',
        name: 'AuthBloc',
      );
    } catch (e) {
      developer.log('❌ AuthBloc: Google Sign-In error: $e', name: 'AuthBloc');
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onSignOutRequested(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await signOutUseCase();
      emit(AuthUnauthenticated());
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  void _onAuthUserChanged(AuthUserChanged event, Emitter<AuthState> emit) {
    developer.log(
      '🔄 AuthBloc: Auth user changed - user: ${event.user?.email ?? 'null'}',
      name: 'AuthBloc',
    );
    if (event.user != null) {
      developer.log(
        '✅ AuthBloc: Emitting AuthAuthenticated from user change',
        name: 'AuthBloc',
      );
      emit(AuthAuthenticated(event.user!));
    } else {
      developer.log(
        '❌ AuthBloc: Emitting AuthUnauthenticated from user change',
        name: 'AuthBloc',
      );
      emit(AuthUnauthenticated());
    }
  }

  @override
  Future<void> close() {
    _authStateSubscription.cancel();
    return super.close();
  }
}
