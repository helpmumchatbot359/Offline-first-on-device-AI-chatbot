class AuthException implements Exception {
  AuthException(this.message);
  final String message;
}

// Rules for what authentication features our app supports
abstract class AuthRepository {
  Future<bool> hasSession();
  Future<void> signUp({
    required String username,
    required String gender,
    required String email,
    required String country,
    required String password,
  });
  Future<void> signIn({required String email, required String password});
  Future<void> signOut();

  /// Fires when the long (30-day) login is over and the person must sign in again.
  Stream<void> get sessionExpired;
}