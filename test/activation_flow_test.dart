import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mama_ai/core/theme/app_theme.dart';
import 'package:mama_ai/features/auth/domain/auth_repository.dart';
import 'package:mama_ai/features/auth/domain/user_profile.dart';
import 'package:mama_ai/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mama_ai/features/auth/presentation/events/auth_event.dart';
import 'package:mama_ai/features/auth/presentation/pages/activation_page.dart';
import 'package:mama_ai/features/auth/presentation/states/auth_state.dart';

/// In-memory stand-in for the backend. No network, no secure storage.
class _FakeAuthRepository implements AuthRepository {
  bool pending = false;
  bool signedIn = false;
  String? pendingEmail;
  DateTime? pendingExpiresAtValue;
  String? lastActivatedCode;
  int resendCalls = 0;
  ActivationResult activationResult = ActivationResult.activated;
  AuthException? activationError;
  AuthException? signInError;

  @override
  Future<bool> hasSession() async => signedIn;

  @override
  Future<UserProfile?> currentUser() async =>
      UserProfile(name: 'Ada', email: pendingEmail ?? 'ada@example.com');

  @override
  Future<void> signUp({
    required String username,
    required String gender,
    required String email,
    required String country,
    required String password,
  }) async {
    pending = true;
    pendingEmail = email;
    pendingExpiresAtValue = DateTime.now().add(const Duration(minutes: 10));
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (signInError != null) throw signInError!;
    signedIn = true;
  }

  @override
  Future<void> signOut() async {
    signedIn = false;
    pending = false;
    pendingEmail = null;
  }

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<bool> hasPendingActivation() async => pending;

  @override
  Future<String?> pendingActivationEmail() async => pendingEmail;

  @override
  Future<DateTime?> pendingActivationExpiresAt() async => pendingExpiresAtValue;

  @override
  Future<ActivationResult> activate({required String code}) async {
    lastActivatedCode = code;
    if (activationError != null) throw activationError!;
    if (activationResult == ActivationResult.activated) {
      signedIn = true;
      pending = false;
    }
    return activationResult;
  }

  @override
  Future<void> resendActivationCode() async {
    resendCalls++;
  }

  @override
  Stream<void> get sessionExpired => const Stream<void>.empty();
}

Future<void> _until(AuthBloc bloc, bool Function(AuthState state) match) async {
  if (match(bloc.state)) return;
  await bloc.stream.firstWhere(match);
}

void main() {
  SignUpSubmitted signup() => SignUpSubmitted(
    username: 'Ada',
    gender: 'Female',
    email: 'ada@example.com',
    country: 'Nigeria',
    password: 'YourPassword123!',
  );

  group('signup and activation states', () {
    test('signup is pending, not authenticated', () async {
      final repo = _FakeAuthRepository();
      final bloc = AuthBloc(repo);
      addTearDown(bloc.close);

      bloc.add(signup());
      await _until(bloc, (s) => s.status == AuthStatus.pendingActivation);

      expect(bloc.state.status, AuthStatus.pendingActivation);
      expect(bloc.state.email, 'ada@example.com');
      expect(bloc.state.pendingExpiresAt, isNotNull);
      expect(repo.signedIn, isFalse);
    });

    test('entering the code signs the person in', () async {
      final repo = _FakeAuthRepository();
      final bloc = AuthBloc(repo);
      addTearDown(bloc.close);

      bloc.add(signup());
      await _until(bloc, (s) => s.status == AuthStatus.pendingActivation);

      bloc.add(ActivationCodeSubmitted('123456'));
      await _until(bloc, (s) => s.status == AuthStatus.authenticated);

      expect(repo.lastActivatedCode, '123456');
      expect(repo.signedIn, isTrue);
      expect(bloc.state.email, 'ada@example.com');
    });

    test('a bad code keeps the person on the verification screen', () async {
      final repo = _FakeAuthRepository()
        ..activationError = AuthException('That code is not valid.');
      final bloc = AuthBloc(repo);
      addTearDown(bloc.close);

      bloc.add(signup());
      await _until(bloc, (s) => s.status == AuthStatus.pendingActivation);

      bloc.add(ActivationCodeSubmitted('000000'));
      await _until(bloc, (s) => s.error != null);

      expect(bloc.state.status, AuthStatus.pendingActivation);
      expect(bloc.state.error, 'That code is not valid.');
      expect(bloc.state.busy, isFalse);
    });

    test('409 sends an already-active account to sign in', () async {
      final repo = _FakeAuthRepository()
        ..activationResult = ActivationResult.alreadyActive;
      final bloc = AuthBloc(repo);
      addTearDown(bloc.close);

      bloc.add(signup());
      await _until(bloc, (s) => s.status == AuthStatus.pendingActivation);

      bloc.add(ActivationCodeSubmitted('123456'));
      await _until(
        bloc,
        (s) => s.status == AuthStatus.unauthenticated && s.error != null,
      );

      expect(
        bloc.state.error,
        'This account is already active. Please sign in.',
      );
      expect(bloc.state.email, 'ada@example.com');
    });

    test('resend increases the counter so the UI can show a note', () async {
      final repo = _FakeAuthRepository();
      final bloc = AuthBloc(repo);
      addTearDown(bloc.close);

      bloc.add(signup());
      await _until(bloc, (s) => s.status == AuthStatus.pendingActivation);
      final before = bloc.state.resendCount;

      bloc.add(ActivationCodeResendRequested());
      await _until(bloc, (s) => s.resendCount > before);

      expect(repo.resendCalls, 1);
      expect(bloc.state.status, AuthStatus.pendingActivation);
    });

    test('restarting resumes a pending signup', () async {
      final repo = _FakeAuthRepository()
        ..pending = true
        ..pendingEmail = 'ada@example.com'
        ..pendingExpiresAtValue = DateTime.now().add(
          const Duration(minutes: 9),
        );
      final bloc = AuthBloc(repo);
      addTearDown(bloc.close);

      bloc.add(AuthStarted());
      await _until(bloc, (s) => s.status != AuthStatus.unknown);

      expect(bloc.state.status, AuthStatus.pendingActivation);
      expect(bloc.state.email, 'ada@example.com');
    });

    test(
      '403 on login resumes activation when a pending token exists',
      () async {
        final repo = _FakeAuthRepository()
          ..pending = true
          ..pendingEmail = 'ada@example.com'
          ..signInError = AuthException(
            'Not activated',
            code: 'pending_activation',
          );
        final bloc = AuthBloc(repo);
        addTearDown(bloc.close);

        bloc.add(SignInSubmitted('ada@example.com', 'YourPassword123!'));
        await _until(bloc, (s) => s.status == AuthStatus.pendingActivation);

        expect(bloc.state.status, AuthStatus.pendingActivation);
        expect(bloc.state.error, isNull);
      },
    );
  });

  testWidgets('activation screen shows six boxes and auto-submits', (
    tester,
  ) async {
    final repo = _FakeAuthRepository()
      ..pending = true
      ..pendingEmail = 'ada@example.com'
      ..pendingExpiresAtValue = DateTime.now().add(const Duration(minutes: 10));
    final bloc = AuthBloc(repo)..add(AuthStarted());
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: BlocProvider.value(value: bloc, child: const ActivationPage()),
      ),
    );
    // Deliberately no pumpAndSettle: the countdown timer ticks every second.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Check your email'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is RichText && w.text.toPlainText().contains('ada@example.com'),
      ),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNWidgets(6));
    expect(find.byType(AnimatedContainer), findsNWidgets(6));
    // No second outline/background should be drawn inside each box by the
    // global InputDecorationTheme (that used to make them look doubled).
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is InputDecorator &&
            (w.decoration.filled == true ||
                w.decoration.border != InputBorder.none ||
                w.decoration.enabledBorder != InputBorder.none ||
                w.decoration.focusedBorder != InputBorder.none),
      ),
      findsNothing,
    );

    // Typing/pasting the whole code into the first box distributes it across
    // the six visible boxes and auto-submits.
    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.lastActivatedCode, '123456');
  });
}
