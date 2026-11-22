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
    on<ActivationCodeSubmitted>(_onActivate);
    on<ActivationCodeResendRequested>(_onResend);
    on<ActivationAbandoned>(_onAbandon);
    on<SignedOut>(_onSignedOut);
    on<AccountDeletionRequested>(_onAccountDeletionRequested);
    on<SessionExpired>(_onSessionExpired);

    // Listen for "your 30 days are over" coming from the network layer.
    _expiredSub = _repo.sessionExpired.listen((_) => add(SessionExpired()));
  }

  final AuthRepository _repo;
  StreamSubscription<void>? _expiredSub;

  static const _genericError = 'Something went wrong. Please try again.';

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    try {
      // A sign-up that was interrupted (app closed, phone restarted) is
      // resumed before anything else: its temporary token is still valid.
      if (await _repo.hasPendingActivation()) {
        final user = await _repo.currentUser();
        emit(
          AuthState(
            status: AuthStatus.pendingActivation,
            displayName: user?.name,
            email: user?.email ?? await _repo.pendingActivationEmail(),
            pendingExpiresAt: await _repo.pendingActivationExpiresAt(),
          ),
        );
        return;
      }

      final hasSession = await _repo.hasSession();
      final user = hasSession ? await _repo.currentUser() : null;
      emit(
        state.copyWith(
          status: hasSession
              ? AuthStatus.authenticated
              : AuthStatus.unauthenticated,
          displayName: user?.name,
          email: user?.email,
        ),
      );
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
      // The account exists but is not active. The app now shows the code
      // screen instead of the chat.
      emit(
        AuthState(
          status: AuthStatus.pendingActivation,
          displayName: event.username,
          email: event.email,
          pendingExpiresAt: await _repo.pendingActivationExpiresAt(),
        ),
      );
    } on AuthException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
    } catch (_) {
      emit(state.copyWith(busy: false, error: _genericError));
    }
  }

  Future<void> _onSignIn(SignInSubmitted event, Emitter<AuthState> emit) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, error: null));
    try {
      await _repo.signIn(email: event.email, password: event.password);
      final user = await _repo.currentUser();
      emit(
        AuthState(
          status: AuthStatus.authenticated,
          displayName: user?.name,
          email: user?.email ?? event.email,
        ),
      );
    } on AuthException catch (e) {
      // 403 from /user/login means the account is still waiting for its code.
      // If this phone still holds that pending sign-up, resume verification
      // instead of showing "wrong password".
      if (e.code == 'pending_activation' &&
          await _repo.hasPendingActivation()) {
        emit(
          AuthState(
            status: AuthStatus.pendingActivation,
            displayName: state.displayName,
            email: event.email,
            pendingExpiresAt: await _repo.pendingActivationExpiresAt(),
          ),
        );
        return;
      }
      emit(state.copyWith(busy: false, error: e.message));
    } catch (_) {
      emit(state.copyWith(busy: false, error: _genericError));
    }
  }

  Future<void> _onActivate(
    ActivationCodeSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, error: null));
    try {
      final result = await _repo.activate(code: event.code);
      if (result == ActivationResult.alreadyActive) {
        // Not an error: the account works, they just need to sign in.
        emit(
          AuthState(
            status: AuthStatus.unauthenticated,
            error: 'This account is already active. Please sign in.',
            displayName: state.displayName,
            email: state.email,
          ),
        );
        return;
      }

      final user = await _repo.currentUser();
      emit(
        AuthState(
          status: AuthStatus.authenticated,
          displayName: user?.name,
          email: user?.email ?? state.email,
        ),
      );
    } on AuthException catch (e) {
      if (e.code == 'no_pending') {
        emit(AuthState(status: AuthStatus.unauthenticated, error: e.message));
        return;
      }
      // Wrong/expired code: stay on the screen so they can try again.
      emit(state.copyWith(busy: false, error: e.message));
    } catch (_) {
      emit(state.copyWith(busy: false, error: _genericError));
    }
  }

  Future<void> _onResend(
    ActivationCodeResendRequested event,
    Emitter<AuthState> emit,
  ) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, error: null));
    try {
      await _repo.resendActivationCode();
      emit(
        state.copyWith(
          busy: false,
          resendCount: state.resendCount + 1,
          pendingExpiresAt: await _repo.pendingActivationExpiresAt(),
        ),
      );
    } on AuthException catch (e) {
      if (e.code == 'no_pending') {
        emit(AuthState(status: AuthStatus.unauthenticated, error: e.message));
        return;
      }
      emit(state.copyWith(busy: false, error: e.message));
    } catch (_) {
      emit(state.copyWith(busy: false, error: _genericError));
    }
  }

  Future<void> _onAbandon(
    ActivationAbandoned event,
    Emitter<AuthState> emit,
  ) async {
    try {
      await _repo.signOut(); // also clears the pending sign-up
    } catch (_) {
      // Even if cleanup fails, the person asked to go back.
    }
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  Future<void> _onSignedOut(SignedOut event, Emitter<AuthState> emit) async {
    try {
      await _repo.signOut();
    } catch (_) {
      // Even if cleanup fails, the person asked to leave.
    }
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  Future<void> _onAccountDeletionRequested(
    AccountDeletionRequested event,
    Emitter<AuthState> emit,
  ) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, error: null));
    try {
      await _repo.deleteAccount();
      emit(const AuthState(status: AuthStatus.unauthenticated));
    } on AuthException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
    } catch (_) {
      emit(
        state.copyWith(
          busy: false,
          error: 'Could not delete your account. Please try again.',
        ),
      );
    }
  }

  Future<void> _onSessionExpired(
    SessionExpired event,
    Emitter<AuthState> emit,
  ) async {
    // Only matters if someone is actually signed in right now.
    if (state.status != AuthStatus.authenticated) return;
    try {
      await _repo
          .signOut(); // tokens are already gone; this resets the chat session
    } catch (_) {}
    emit(
      const AuthState(
        status: AuthStatus.unauthenticated,
        error: 'Your session has expired. Please sign in again.',
      ),
    );
  }

  @override
  Future<void> close() async {
    await _expiredSub?.cancel();
    return super.close();
  }
}
