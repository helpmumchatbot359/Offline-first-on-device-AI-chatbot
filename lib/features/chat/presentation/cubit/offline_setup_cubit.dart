import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/ai/model_setup_service.dart';

enum OfflineSetupStatus { checking, missing, downloading, verifying, ready, failed }

class OfflineSetupState extends Equatable {
  const OfflineSetupState({
    this.status = OfflineSetupStatus.checking,
    this.progress = 0,
    this.message,
  });

  final OfflineSetupStatus status;
  final double progress; // 0..1
  final String? message;

  @override
  List<Object?> get props => [status, progress, message];
}

/// Controls the "download the offline assistant" banner
class OfflineSetupCubit extends Cubit<OfflineSetupState> {
  OfflineSetupCubit(this._service) : super(const OfflineSetupState());

  final ModelSetupService _service;
  CancelToken? _cancel;

  Future<void> check() async {
    try {
      final path = await _service.existingPath();
      _safeEmit(OfflineSetupState(
        status: path != null ? OfflineSetupStatus.ready : OfflineSetupStatus.missing,
      ));
    } catch (_) {
      _safeEmit(const OfflineSetupState(status: OfflineSetupStatus.missing));
    }
  }

  Future<void> download() async {
    if (state.status == OfflineSetupStatus.downloading ||
        state.status == OfflineSetupStatus.verifying) {
      return;
    }
    _cancel = CancelToken();
    _safeEmit(const OfflineSetupState(status: OfflineSetupStatus.downloading));
    try {
      await _service.downloadModel(
        cancelToken: _cancel,
        onProgress: (p) =>
            _safeEmit(OfflineSetupState(status: OfflineSetupStatus.downloading, progress: p)),
        onVerifying: () =>
            _safeEmit(const OfflineSetupState(status: OfflineSetupStatus.verifying, progress: 1)),
      );
      _safeEmit(const OfflineSetupState(status: OfflineSetupStatus.ready));
    } on ModelSetupException catch (e) {
      _safeEmit(OfflineSetupState(status: OfflineSetupStatus.failed, message: e.message));
    } catch (_) {
      _safeEmit(const OfflineSetupState(
        status: OfflineSetupStatus.failed,
        message: 'The download failed. Tap resume to try again.',
      ));
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
