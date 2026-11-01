// lib/features/auth/presentation/states/auth_state.dart
import 'package:equatable/equatable.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.busy = false,
    this.error,
  });

  final AuthStatus status;
  final bool busy;
  final String? error;

  AuthState copyWith({AuthStatus? status, bool? busy, String? error}) {
    return AuthState(
      status: status ?? this.status,
      busy: busy ?? false,
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, busy, error];
}