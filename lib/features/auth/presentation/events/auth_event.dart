import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthStarted extends AuthEvent {}

class SignUpSubmitted extends AuthEvent {
  SignUpSubmitted({
    required this.username,
    required this.gender,
    required this.email,
    required this.country,
    required this.password,
  });
  final String username, gender, email, country, password;

  @override
  List<Object?> get props => [username, gender, email, country, password];
}

class SignInSubmitted extends AuthEvent {
  SignInSubmitted(this.email, this.password);
  final String email, password;

  @override
  List<Object?> get props => [email, password];
}

/// The six digits from the email.
class ActivationCodeSubmitted extends AuthEvent {
  ActivationCodeSubmitted(this.code);
  final String code;

  @override
  List<Object?> get props => [code];
}

/// "Send a new code" — the backend reuses the sign-up endpoint.
class ActivationCodeResendRequested extends AuthEvent {}

/// "Use a different email" — forgets the pending sign-up and goes back.
class ActivationAbandoned extends AuthEvent {}

class SignedOut extends AuthEvent {}

class AccountDeletionRequested extends AuthEvent {}

/// Internal: the server refused to renew the login (30 days are over, or it was revoked).
class SessionExpired extends AuthEvent {}
