// REPLACES  lib/main.dart  (search for "TELEMETRY" to see what changed)
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/network/api_client.dart';
import 'core/security/token_storage.dart';
import 'core/theme/theme_bloc/theme_bloc.dart';
import 'features/auth/data/auth_repository_impl.dart';
import 'features/chat/data/ai/model_setup_service.dart';
import 'features/chat/data/ai/native_offline_ai_service.dart';
import 'features/chat/data/chat_repository_impl.dart';
import 'features/chat/data/local/chat_local_data_source.dart';
import 'features/chat/data/local/diagnostic_logger.dart';
import 'features/chat/data/remote_chat_data_source.dart';
import 'features/chat/data/sync/sync_service.dart';
import 'features/chat/data/telemetry/device_telemetry.dart'; // TELEMETRY: device envelope
import 'features/chat/data/telemetry/telemetry_recorder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Secure storage (token, theme, local ids)
  final tokenStorage = TokenStorage();

  var localAccountOwner = '';
  try {
    final savedEmail = await tokenStorage.readProfileEmail();
    if (savedEmail != null && savedEmail.trim().isNotEmpty) {
      localAccountOwner = TokenStorage.accountOwnerForEmail(savedEmail);
    }
  } catch (_) {}

  // 2) Read saved theme before the first frame to prevent white flashes
  var savedTheme = ThemeMode.light;
  try {
    savedTheme = ThemeBloc.parseMode(await tokenStorage.readTheme());
  } catch (_) {}

  // 3) Local ObjectBox database & diagnostic JSONL logger initialization
  final localDataSource = ChatLocalDataSource();
  await localDataSource.init(ownerId: localAccountOwner);
  // Answers that were cut off when Android closed the app last time: rescue them
  // BEFORE the chat screen loads its history.
  await localDataSource.recoverInterruptedTurns();

  // TELEMETRY / DIAGNOSTICS: one shared reader for phone facts.
  // DeviceTelemetry reads manufacturer/model/RAM/memory/PSS/thermal/battery
  // through the native "mama_ai/device_info" channel.
  final deviceTelemetry = DeviceTelemetry(backend: 'cpu');

  // The SAME reader is given to the diagnostic logger, so every record sent to
  // /v1/diagnostic-logs also contains the device/runtime block.
  final diagnosticLogger = DiagnosticLogger(deviceTelemetry: deviceTelemetry);

  // TELEMETRY: the one object that creates telemetry events.
  final telemetry = TelemetryRecorder(
    localDataSource,
    deviceTelemetry: deviceTelemetry,
    diagnosticLogger: diagnosticLogger,
  );
  // If the app died in the middle of an on-phone answer last time (crash /
  // Android killed it for memory), record a runtime_failure NOW, before the
  // first sync, so it is uploaded together with everything else.
  await telemetry.recoverFromPreviousRun();

  // 4) Network, Model Setup, and Native AI services
  final apiClient = ApiClient(tokenStorage);
  final modelSetupService = ModelSetupService();
  final nativeAiService = NativeOfflineAiService();

  // 5) Repositories and background sync service dependency injection
  final authRepository = AuthRepositoryImpl(
    apiClient,
    tokenStorage,
    clearLocalAccountData: localDataSource.clearAccountData,
    setLocalAccountOwner: (ownerId) async {
      localDataSource.setAccountOwner(ownerId);
    },
  );
  final chatRepository = ChatRepositoryImpl(
    apiClient: apiClient,
    localDataSource: localDataSource,
    tokenStorage: tokenStorage,
    nativeAiService: nativeAiService,
    diagnosticLogger: diagnosticLogger,
    modelSetupService: modelSetupService,
    telemetry: telemetry,
    remoteChatDataSource: RemoteChatDataSource(apiClient),
  );

  final syncService = SyncService(
    apiClient,
    Connectivity(),
    localDataSource,
    diagnosticLogger,
    telemetry: telemetry,
    tokenStorage: tokenStorage,
    modelSetupService: modelSetupService,
  );
  // Upload a freshly created telemetry event immediately (if online).
  // Without this, an event could wait until the next connectivity change.
  telemetry.onEventQueued = syncService.syncAll;
  syncService.startBackgroundSync();

  runApp(
    MamaApp(
      tokenStorage: tokenStorage,
      authRepository: authRepository,
      chatRepository: chatRepository,
      modelSetupService: modelSetupService,
      syncService: syncService,
      initialThemeMode: savedTheme,
    ),
  );
}
