import 'dart:async';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/security/token_storage.dart';
import '../../data/ai/model_setup_service.dart';

enum OfflineSetupStatus {
  checking,
  missing,
  downloading,
  verifying,
  ready,
  failed,
}

class OfflineSetupState extends Equatable {
  const OfflineSetupState({
    this.status = OfflineSetupStatus.checking,
    this.progress = 0,
    this.message,
    this.isBannerDismissed = false,
  });

  final OfflineSetupStatus status;
  final double progress; // 0..1
  final String? message;
  final bool isBannerDismissed;

  @override
  List<Object?> get props => [status, progress, message, isBannerDismissed];

  OfflineSetupState copyWith({bool? isBannerDismissed}) => OfflineSetupState(
    status: status,
    progress: progress,
    message: message,
    isBannerDismissed: isBannerDismissed ?? this.isBannerDismissed,
  );
}

/// Controls the "download the offline assistant" banner
class OfflineSetupCubit extends Cubit<OfflineSetupState> {
  OfflineSetupCubit(this._service, this._storage)
    : super(const OfflineSetupState());

  final ModelSetupService _service;
  final TokenStorage _storage;
  CancelToken? _cancel;

  /// Hides the chat card AND remembers the choice for the next launch.
  /// It never pauses the download: the work keeps running and its controls
  /// stay available in Settings.
  void dismissBanner() {
    _safeEmit(state.copyWith(isBannerDismissed: true));
    unawaited(
      _storage.saveOfflineBannerHidden(true).catchError((_) {
        // Losing the preference is harmless: the card simply returns next
        // launch. It must never crash the screen.
      }),
    );
  }

  Future<void> check() async {
    // Read the saved preference first so the card does not flicker on screen
    // for a frame before disappearing.
    var hidden = state.isBannerDismissed;
    try {
      hidden = hidden || await _storage.readOfflineBannerHidden();
    } catch (_) {
      // Storage can fail on some devices; keep the in-session value.
    }
    try {
      final path = await _service.existingPath();
      _safeEmit(
        OfflineSetupState(
          status: path != null
              ? OfflineSetupStatus.ready
              : OfflineSetupStatus.missing,
          isBannerDismissed: hidden,
        ),
      );
    } catch (_) {
      _safeEmit(
        OfflineSetupState(
          status: OfflineSetupStatus.missing,
          isBannerDismissed: hidden,
        ),
      );
    }
  }

  Future<void> download() async {
    if (state.status == OfflineSetupStatus.downloading ||
        state.status == OfflineSetupStatus.verifying) {
      return;
    }
    _cancel = CancelToken();
    _safeEmit(
      OfflineSetupState(
        status: OfflineSetupStatus.downloading,
        isBannerDismissed: state.isBannerDismissed,
      ),
    );
    try {
      await _service.downloadModel(
        cancelToken: _cancel,
        onProgress: (p) => _safeEmit(
          OfflineSetupState(
            status: OfflineSetupStatus.downloading,
            progress: p,
            isBannerDismissed: state.isBannerDismissed,
          ),
        ),
        onVerifying: () => _safeEmit(
          OfflineSetupState(
            status: OfflineSetupStatus.verifying,
            progress: 1,
            isBannerDismissed: state.isBannerDismissed,
          ),
        ),
      );
      _safeEmit(
        OfflineSetupState(
          status: OfflineSetupStatus.ready,
          isBannerDismissed: state.isBannerDismissed,
        ),
      );
    } on ModelSetupException catch (e) {
      _safeEmit(
        OfflineSetupState(
          status: OfflineSetupStatus.failed,
          message: e.message,
          isBannerDismissed: state.isBannerDismissed,
        ),
      );
    } catch (_) {
      _safeEmit(
        OfflineSetupState(
          status: OfflineSetupStatus.failed,
          message: 'The download failed. Tap resume to try again.',
          isBannerDismissed: state.isBannerDismissed,
        ),
      );
    }
  }

  /// Keeps the half-downloaded file, so "resume" continues where it stopped.
  void pause() => _cancel?.cancel();

  void _safeEmit(OfflineSetupState s) {
    if (!isClosed) emit(s);
  }

  @override
  Future<void> close() {
    _cancel?.cancel();
    return super.close();
  }
}
