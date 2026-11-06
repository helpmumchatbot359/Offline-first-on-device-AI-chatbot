// lib/features/auth/presentation/states/auth_state.dart
import 'package:equatable/equatable.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.busy = false,
    this.error,
    this.justSignedUp = false,
  });

  final AuthStatus status;
  final bool busy;
  final String? error;

  /// True for the single state produced right after a successful sign-up.
  ///
  /// The screen uses this to jump to the sign-in tab and show a friendly
  /// "account created" note. It is intentionally a one-shot flag: every
  /// following state falls back to false, so nothing lingers.
  final bool justSignedUp;

  AuthState copyWith({
    AuthStatus? status,
    bool? busy,
    String? error,
    bool justSignedUp = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      busy: busy ?? false,
      error: error,
      justSignedUp: justSignedUp,
    );
  }

  @override
  List<Object?> get props => [status, busy, error, justSignedUp];
}
