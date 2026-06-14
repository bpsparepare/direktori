import 'package:flutter/foundation.dart'; // Add this for kIsWeb
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../models/user_model.dart';
import '../../../../core/config/supabase_config.dart';

class AuthRepositoryImpl implements AuthRepository {
  final SupabaseClient _supabaseClient = SupabaseConfig.client;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    // Fix untuk Web: serverClientId TIDAK boleh ada di Web (harus null)
    serverClientId: kIsWeb ? null : SupabaseConfig.googleClientId,
    // Fix untuk Web: clientId HARUS ada di Web
    clientId: kIsWeb ? SupabaseConfig.googleClientId : null,
  );

  @override
  Future<UserEntity?> getCurrentUser() async {
    final user = _supabaseClient.auth.currentUser;
    if (user != null) {
      return await _getAuthorizedUserOrNull(user);
    }
    return null;
  }

  @override
  Future<UserEntity> signInWithEmail(String email, String password) async {
    try {
      final response = await _supabaseClient.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        return await _requireAuthorizedUser(response.user!);
      } else {
        throw Exception('Login gagal');
      }
    } on AuthException catch (e) {
      throw Exception('Login gagal: ${e.message}');
    } catch (e) {
      throw Exception('Terjadi kesalahan: $e');
    }
  }

  @override
  Future<UserEntity> signUpWithEmail(String email, String password) async {
    try {
      final response = await _supabaseClient.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user != null) {
        return UserModel.fromSupabaseUser(response.user!);
      } else {
        throw Exception('Registrasi gagal');
      }
    } on AuthException catch (e) {
      throw Exception('Registrasi gagal: ${e.message}');
    } catch (e) {
      throw Exception('Terjadi kesalahan: $e');
    }
  }

  @override
  Future<UserEntity> signInWithGoogle() async {
    try {
      developer.log('🚀 Starting Google Sign-In process', name: 'GoogleSignIn');

      // Sign in with Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        developer.log(
          '❌ Google Sign-In cancelled by user',
          name: 'GoogleSignIn',
        );
        throw Exception('Login Google dibatalkan');
      }

      developer.log(
        '✅ Google user obtained: ${googleUser.email}',
        name: 'GoogleSignIn',
      );

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null || idToken == null) {
        developer.log(
          '❌ Failed to get Google tokens - accessToken: $accessToken, idToken: $idToken',
          name: 'GoogleSignIn',
        );
        throw Exception('Gagal mendapatkan token Google');
      }

      developer.log(
        '✅ Google tokens obtained successfully',
        name: 'GoogleSignIn',
      );
      developer.log(
        '🔄 Signing in to Supabase with Google credentials...',
        name: 'GoogleSignIn',
      );

      // Sign in to Supabase with Google credentials
      final response = await _supabaseClient.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      if (response.user != null) {
        developer.log(
          '✅ Supabase sign-in successful! User ID: ${response.user!.id}',
          name: 'GoogleSignIn',
        );
        developer.log(
          '✅ User email: ${response.user!.email}',
          name: 'GoogleSignIn',
        );
        developer.log(
          '✅ Session created: ${response.session != null}',
          name: 'GoogleSignIn',
        );

        final userEntity = await _requireAuthorizedUser(response.user!);
        developer.log(
          '✅ UserEntity created successfully',
          name: 'GoogleSignIn',
        );
        return userEntity;
      } else {
        developer.log(
          '❌ Supabase sign-in failed - no user returned',
          name: 'GoogleSignIn',
        );
        throw Exception('Login Google gagal');
      }
    } catch (e) {
      developer.log('❌ Google Sign-In error: $e', name: 'GoogleSignIn');
      throw Exception('Login Google gagal: $e');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _supabaseClient.auth.signOut();
    } catch (e) {
      throw Exception('Logout gagal: $e');
    }
  }

  @override
  Stream<UserEntity?> get authStateChanges {
    return _supabaseClient.auth.onAuthStateChange.asyncMap((data) async {
      final user = data.session?.user;
      if (user != null) {
        return await _getAuthorizedUserOrNull(user);
      }
      return null;
    });
  }

  Future<UserEntity> _requireAuthorizedUser(User user) async {
    final authorizedUser = await _getAuthorizedUserOrNull(user);
    if (authorizedUser == null) {
      throw Exception('Akun ini tidak terdaftar sebagai petugas SE2026 aktif');
    }
    return authorizedUser;
  }

  Future<UserEntity?> _getAuthorizedUserOrNull(User user) async {
    try {
      final appUser = await _supabaseClient
          .from('users')
          .select('id')
          .eq('auth_uid', user.id)
          .maybeSingle();

      if (appUser == null || appUser['id'] == null) {
        await _safeSignOutUnauthorizedUser();
        return null;
      }

      final petugas = await _supabaseClient
          .from('se2026_petugas')
          .select('id, is_active')
          .eq('user_id', appUser['id'])
          .maybeSingle();

      if (petugas == null || petugas['id'] == null || petugas['is_active'] != true) {
        await _safeSignOutUnauthorizedUser();
        return null;
      }

      return UserModel.fromSupabaseUser(user);
    } catch (e) {
      developer.log('❌ SE2026 auth validation error: $e', name: 'AuthRepository');
      await _safeSignOutUnauthorizedUser();
      return null;
    }
  }

  Future<void> _safeSignOutUnauthorizedUser() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}

    try {
      await _supabaseClient.auth.signOut();
    } catch (_) {}
  }
}
