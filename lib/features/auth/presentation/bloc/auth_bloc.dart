import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/auth_repository.dart';
import '../events/auth_event.dart';
import '../states/auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this._repo) : super(const AuthState()) {
    on<AuthStarted>(_onStarted);
    on<SignUpSubmitted>(_onSignUp);
    on<SignInSubmitted>(_onSignIn);
    on<SignedOut>(_onSignedOut);
    on<SessionExpired>(_onSessionExpired);

    // Listen for "your 30 days are over" coming from the network layer.
    _expiredSub = _repo.sessionExpired.listen((_) => add(SessionExpired()));
  }

  final AuthRepository _repo;
  StreamSubscription<void>? _expiredSub;

  static const _genericError = 'Something went wrong. Please try again.';

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    try {
      final hasSession = await _repo.hasSession();
      emit(state.copyWith(
        status: hasSession ? AuthStatus.authenticated : AuthStatus.unauthenticated,
      ));
    } catch (_) {
      // If storage fails we must NOT stay on the splash screen forever.
      emit(state.copyWith(status: AuthStatus.unauthenticated));
    }
  }

  Future<void> _onSignUp(SignUpSubmitted event, Emitter<AuthState> emit) async {
    if (state.busy) return; // ignore double taps
    emit(state.copyWith(busy: true, error: null));
    try {
      await _repo.signUp(
        username: event.username,
        gender: event.gender,
        email: event.email,
        country: event.country,
        password: event.password,
      );
      emit(state.copyWith(
        status: AuthStatus.unauthenticated,
        error: 'Sign up successful! Please sign in.',
      ));
    } on AuthException catch (e) {
      emit(state.copyWith(error: e.message));
    } catch (_) {
      emit(state.copyWith(error: _genericError)); // busy goes back to false
    }
  }

  Future<void> _onSignIn(SignInSubmitted event, Emitter<AuthState> emit) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, error: null));
    try {
      await _repo.signIn(email: event.email, password: event.password);
      emit(state.copyWith(status: AuthStatus.authenticated));
    } on AuthException catch (e) {
      emit(state.copyWith(error: e.message));
    } catch (_) {
      emit(state.copyWith(error: _genericError));
    }
  }

  Future<void> _onSignedOut(SignedOut event, Emitter<AuthState> emit) async {
    try {
      await _repo.signOut();
    } catch (_) {
      // Even if cleanup fails, the person asked to leave.
    }
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  Future<void> _onSessionExpired(SessionExpired event, Emitter<AuthState> emit) async {
    // Only matters if someone is actually signed in right now.
    if (state.status != AuthStatus.authenticated) return;
    try {
      await _repo.signOut(); // tokens are already gone; this resets the chat session
    } catch (_) {}
    emit(const AuthState(
      status: AuthStatus.unauthenticated,
      error: 'Your session has expired. Please sign in again.',
    ));
  }

  @override
  Future<void> close() async {
    await _expiredSub?.cancel();
    return super.close();
  }
}