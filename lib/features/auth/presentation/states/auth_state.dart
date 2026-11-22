import 'package:equatable/equatable.dart';

enum AuthStatus {
  unknown,
  unauthenticated,

  /// Signed up, but the emailed code has not been entered yet. There is a
  /// temporary token on the phone, NOT a real session.
  pendingActivation,

  authenticated,
}

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.busy = false,
    this.error,
    this.resendCount = 0,
    this.displayName,
    this.email,
    this.pendingExpiresAt,
  });

  final AuthStatus status;
  final bool busy;
  final String? error;

  /// Increases by one every time a new code is requested. The activation
  /// screen compares old/new values, so the "code sent" note appears for
  /// every resend (a bool would only fire once).
  final int resendCount;

  /// Friendly identity shown in the drawer, app bar and settings. It is
  /// optional: older accounts may only have an email on this phone.
  final String? displayName;
  final String? email;

  /// When the pending code stops working (server: 10 minutes).
  final DateTime? pendingExpiresAt;

  AuthState copyWith({
    AuthStatus? status,
    bool? busy,
    String? error,
    int? resendCount,
    String? displayName,
    String? email,
    DateTime? pendingExpiresAt,
  }) {
    return AuthState(
      status: status ?? this.status,
      busy: busy ?? false,
      error: error,
      resendCount: resendCount ?? this.resendCount,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      pendingExpiresAt: pendingExpiresAt ?? this.pendingExpiresAt,
    );
  }

  @override
  List<Object?> get props => [
    status,
    busy,
    error,
    resendCount,
    displayName,
    email,
    pendingExpiresAt,
  ];
}
