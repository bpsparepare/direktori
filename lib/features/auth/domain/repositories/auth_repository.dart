import '../entities/user_entity.dart';

abstract class AuthRepository {
  Future<UserEntity?> getCurrentUser();
  Future<UserEntity> signInWithEmail(String email, String password);
  Future<UserEntity> signUpWithEmail(String email, String password);
  Future<UserEntity> signInWithGoogle();
  Future<void> signOut();
  Stream<UserEntity?> get authStateChanges;
}