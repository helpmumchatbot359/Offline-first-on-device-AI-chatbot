import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/security/token_storage.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_bloc/theme_bloc.dart';
import 'core/theme/theme_bloc/theme_event.dart';
import 'core/theme/theme_bloc/theme_state.dart';
import 'core/widgets/mama_logo.dart';
import 'features/auth/domain/auth_repository.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/events/auth_event.dart';
import 'features/auth/presentation/states/auth_state.dart';
import 'features/chat/data/ai/model_setup_service.dart';
import 'features/chat/data/sync/sync_service.dart';
import 'features/chat/domain/chat_repository.dart';
import 'features/chat/presentation/bloc/chat_bloc.dart';
import 'features/chat/presentation/cubit/offline_setup_cubit.dart';
import 'features/chat/presentation/events/chat_event.dart';
import 'features/chat/presentation/pages/chat_page.dart';
import 'features/onboarding/presentation/onboarding_page.dart';

class MamaApp extends StatelessWidget {
  const MamaApp({
    super.key,
    required this.tokenStorage,
    required this.authRepository,
    required this.chatRepository,
    required this.modelSetupService,
    required this.syncService,
    this.initialThemeMode = ThemeMode.light,
  });

  final TokenStorage tokenStorage;
  final AuthRepository authRepository;
  final ChatRepository chatRepository; // was `dynamic`: now the compiler checks it
  final ModelSetupService modelSetupService;
  final SyncService syncService;
  final ThemeMode initialThemeMode;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => ThemeBloc(tokenStorage, initialMode: initialThemeMode)
            ..add(const ThemeLoaded()),
        ),
        BlocProvider(create: (_) => AuthBloc(authRepository)..add(AuthStarted())),
      ],
      child: BlocBuilder<ThemeBloc, ThemeState>(
        buildWhen: (p, c) => p.themeMode != c.themeMode,
        builder: (context, themeState) => MaterialApp(
          title: 'MamaBot',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeState.themeMode,
          home: AuthGate(
            chatRepository: chatRepository,
            modelSetupService: modelSetupService,
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.chatRepository,
    required this.modelSetupService,
  });

  final ChatRepository chatRepository;
  final ModelSetupService modelSetupService;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listenWhen: (p, c) => p.status != c.status,
      listener: (context, s) {
        Navigator.of(context).popUntil((route) => route.isFirst);

        // If we were kicked out (e.g. the 30 days ran out), explain why.
        final message = s.error;
        if (s.status == AuthStatus.unauthenticated && message != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          });
        }
      },
      buildWhen: (p, c) => p.status != c.status, // typing errors must not rebuild the chat
      builder: (context, s) {
        switch (s.status) {
          case AuthStatus.unknown:
            return const Scaffold(body: Center(child: MamaLogo(size: 110)));
          case AuthStatus.authenticated:
            return MultiBlocProvider(
              providers: [
                BlocProvider(
                  create: (_) => ChatBloc(chatRepository)..add(const ChatStarted()),
                ),
                BlocProvider(
                  create: (_) => OfflineSetupCubit(modelSetupService)..check(),
                ),
              ],
              child: const ChatPage(),
            );
          case AuthStatus.unauthenticated:
            return const OnboardingPage();
        }
      },
    );
  }
}