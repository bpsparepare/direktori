import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../models/user_model.dart';
import '../../../../core/config/supabase_config.dart';

class SupbasePureAuthRepository implements AuthRepository {
  final SupabaseClient _supabaseClient = SupabaseConfig.client;

  @override
  Future<UserEntity?> getCurrentUser() async {
    final user = _supabaseClient.auth.currentUser;
    if (user != null) {
      return UserModel.fromSupabaseUser(user);
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
        return UserModel.fromSupabaseUser(response.user!);
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
      // Pure Supabase OAuth - tidak perlu google_sign_in package
      final response = await _supabaseClient.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'id.bpsparepare.direktori://login-callback/',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      if (response) {
        // Tunggu sampai user berhasil login
        final user = _supabaseClient.auth.currentUser;
        if (user != null) {
          return UserModel.fromSupabaseUser(user);
        } else {
          throw Exception('Login Google gagal - user tidak ditemukan');
        }
      } else {
        throw Exception('Login Google dibatalkan');
      }
    } catch (e) {
      throw Exception('Login Google gagal: $e');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _supabaseClient.auth.signOut();
    } catch (e) {
      throw Exception('Logout gagal: $e');
    }
  }

  @override
  Stream<UserEntity?> get authStateChanges {
    return _supabaseClient.auth.onAuthStateChange.map((data) {
      final user = data.session?.user;
      if (user != null) {
        return UserModel.fromSupabaseUser(user);
      }
      return null;
    });
  }
}