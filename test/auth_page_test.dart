import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mama_ai/core/security/token_storage.dart';
import 'package:mama_ai/core/theme/app_theme.dart';
import 'package:mama_ai/core/theme/theme_bloc/theme_bloc.dart';
import 'package:mama_ai/features/auth/domain/auth_repository.dart';
import 'package:mama_ai/features/auth/domain/user_profile.dart';
import 'package:mama_ai/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mama_ai/features/auth/presentation/pages/auth_page.dart';
import 'package:mama_ai/features/auth/presentation/states/auth_state.dart';

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<bool> hasSession() async => false;

  @override
  Future<UserProfile?> currentUser() async => null;

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<void> signUp({
    required String username,
    required String gender,
    required String email,
    required String country,
    required String password,
  }) async {}

  @override
  Future<bool> hasPendingActivation() async => false;

  @override
  Future<String?> pendingActivationEmail() async => null;

  @override
  Future<DateTime?> pendingActivationExpiresAt() async => null;

  @override
  Future<ActivationResult> activate({required String code}) async =>
      ActivationResult.activated;

  @override
  Future<void> resendActivationCode() async {}

  @override
  Stream<void> get sessionExpired => const Stream<void>.empty();
}

void main() {
  Future<AuthBloc> pumpAuthPage(
    WidgetTester tester, {
    Size size = const Size(360, 640),
    bool signIn = true,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authBloc = AuthBloc(_FakeAuthRepository());
    addTearDown(authBloc.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ThemeBloc(TokenStorage())),
          BlocProvider.value(value: authBloc),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          // Turning motion off makes the test deterministic and also
          // exercises the reduced-motion branch of the page.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: AuthPage(initialSignIn: signIn),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return authBloc;
  }

  testWidgets('sign-in form fits a small phone', (tester) async {
    await pumpAuthPage(tester);

    expect(find.text('Welcome back.'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Sign in'), findsNWidgets(2)); // tab + button
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching to sign up reveals the extra fields', (tester) async {
    await pumpAuthPage(tester);

    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    expect(find.text("Let's get you\nstarted."), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(4));
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every sign-up field has the same vertical gap', (tester) async {
    await pumpAuthPage(tester);

    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    // Username, Country, Email and Password are TextFormFields; Gender is the
    // dropdown between Username and Country. Measuring their boxes proves the
    // Country -> Email gap matches every other pair, including the one that
    // spans the sign-up block and the outer form column.
    final username = tester.getRect(find.byType(TextFormField).at(0));
    final gender = tester.getRect(find.byType(DropdownButtonFormField<String>));
    final country = tester.getRect(find.byType(TextFormField).at(1));
    final email = tester.getRect(find.byType(TextFormField).at(2));

    final gaps = <double>[
      gender.top - username.bottom,
      country.top - gender.bottom,
      email.top - country.bottom,
    ];

    for (final gap in gaps) {
      expect(
        gap,
        moreOrLessEquals(14, epsilon: 0.1),
        reason: 'Every pair of sign-up fields should be 14 px apart.',
      );
    }
  });

  testWidgets('empty submit shows inline validation', (tester) async {
    await pumpAuthPage(tester);

    await tester.ensureVisible(find.text('Sign in').last);
    await tester.tap(find.text('Sign in').last);
    await tester.pumpAndSettle();

    expect(find.text('Email address is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a successful sign up moves to pending verification', (
    tester,
  ) async {
    final bloc = await pumpAuthPage(tester);

    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ada');
    await tester.enterText(fields.at(1), 'Nigeria');
    await tester.enterText(fields.at(2), 'ada@example.com');
    await tester.enterText(fields.at(3), 'secret123');

    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Female').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    // The app's AuthGate swaps to the six-box verification screen when it
    // sees this status; this widget-only test checks the state it reacts to.
    expect(bloc.state.status, AuthStatus.pendingActivation);
    expect(bloc.state.email, 'ada@example.com');
    expect(bloc.state.busy, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign up is blocked until the terms are accepted', (
    tester,
  ) async {
    await pumpAuthPage(tester);

    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ada');
    await tester.enterText(fields.at(1), 'Nigeria');
    await tester.enterText(fields.at(2), 'ada@example.com');
    await tester.enterText(fields.at(3), 'secret123');

    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Female').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(
      find.text('Please accept the Terms of Use and Privacy Policy.'),
      findsOneWidget,
    );
    expect(find.text('Account created. Sign in to continue.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text and a tablet width do not overflow', (tester) async {
    await pumpAuthPage(
      tester,
      size: const Size(800, 1000),
      signIn: false,
      textScale: 1.3,
    );

    expect(find.text('Create account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign up with large text on a small phone does not overflow', (
    tester,
  ) async {
    await pumpAuthPage(tester, signIn: false, textScale: 1.3);

    expect(find.text('Create account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
