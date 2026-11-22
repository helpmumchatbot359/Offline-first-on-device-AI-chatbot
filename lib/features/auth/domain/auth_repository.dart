import 'user_profile.dart';

class AuthException implements Exception {
  AuthException(this.message, {this.code});
  final String message;

  /// Optional machine-readable reason. Used by the UI to react differently to
  /// "this account still needs its email code" versus a normal failure.
  final String? code;
}

/// What happened when the person typed their email code.
enum ActivationResult {
  /// The account is now active and the real access token has been stored.
  activated,

  /// The server said 409: this account was already activated. Treat it as
  /// good news and send the person to sign in.
  alreadyActive,
}

// Rules for what authentication features our app supports
abstract class AuthRepository {
  Future<bool> hasSession();

  /// The name/email shown in the drawer, app bar and settings.
  Future<UserProfile?> currentUser();

  Future<void> signUp({
    required String username,
    required String gender,
    required String email,
    required String country,
    required String password,
  });
  Future<void> signIn({required String email, required String password});
  Future<void> signOut();

  /// Permanently deletes the signed-in account and clears its on-device data.
  Future<void> deleteAccount();

  /// True while a sign-up is waiting for its emailed code.
  Future<bool> hasPendingActivation();

  /// The email that the pending code was sent to, or null when there is none.
  Future<String?> pendingActivationEmail();

  /// When the pending code stops being accepted (server: 10 minutes).
  Future<DateTime?> pendingActivationExpiresAt();

  /// Sends the code that was typed on the activation screen.
  Future<ActivationResult> activate({required String code});

  /// "Send a new code" is the same call as sign-up (the backend has no
  /// separate resend route). The pending JWT is replaced by the new one.
  Future<void> resendActivationCode();

  /// Fires when the long (30-day) login is over and the person must sign in again.
  Stream<void> get sessionExpired;
}
