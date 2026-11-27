import 'dart:async';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ModelSetupException implements Exception {
  const ModelSetupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Gets the offline files onto the phone:
///  * the ~486 MB Qwen model (downloaded, resumable, hash-checked)
///  * the knowledge database (copied from the app bundle)
class ModelSetupService {
  ModelSetupService({Dio? dio}) : _dio = dio ?? Dio();
  final Dio _dio;

  // Small-model branch: Qwen3.5 0.8B replaces the 2.5 GB Gemma artifact.
  // This is the hosted download used by Play Store installs.
  static const modelUrl =
      'https://offline-ai-mamabot-355119164071.s3.amazonaws.com/models/Qwen3.5-0.8B_mixed48_h1024.litertlm';
  static const expectedSha256 =
      '61c65dbcaa86461184df1b60a82941c5d3e65fb535411d1b2192ccf222e98b35';
  static const fileName = 'Qwen3.5-0.8B_mixed48_h1024.litertlm';

  static const expectedSizeBytes = 486539264;

  // Declare this file under `flutter: assets:` in pubspec.yaml.
  static const knowledgeAsset = 'assets/knowledge/knowledge.sqlite3';
  static const knowledgeFileName = 'knowledge.sqlite3';
  static const knowledgeSizeBytes = 36794368;
  static const runtimeFileName = 'runtime.sqlite3';

  Future<Directory> _dir() => getApplicationSupportDirectory();

  /// Path of the finished model, or null if it is not (fully) there.
  /// Compares size only: hashing 2.5 GB on every launch would be far too slow.
  /// The hash is checked once, right after download.
  Future<String?> existingPath() async {
    final file = File(p.join((await _dir()).path, fileName));
    if (await file.exists() && await file.length() == expectedSizeBytes) {
      return file.path;
    }
    return null;
  }

  /// Downloads with resume + progress. [onVerifying] fires when the download is
  /// done and the safety check begins.
  Future<String> downloadModel({
    void Function(double progress)? onProgress,
    void Function()? onVerifying,
    CancelToken? cancelToken,
  }) async {
    final dir = await _dir();
    final target = File(p.join(dir.path, fileName));
    final temp = File('${target.path}.part');

    if (await existingPath() != null) return target.path;

    var downloaded = await temp.exists() ? await temp.length() : 0;
    if (downloaded > expectedSizeBytes) {
      await temp.delete();
      downloaded = 0;
    }
    if (downloaded < expectedSizeBytes) {
      await _fetch(temp, downloaded, onProgress, cancelToken);
    }

    onVerifying?.call();
    if (!await _matchesSha256(temp)) {
      // Delete it, otherwise every retry would "resume" the same broken file.
      if (await temp.exists()) await temp.delete();
      throw const ModelSetupException(
          'The downloaded file was damaged. Please download it again.');
    }

    if (await target.exists()) await target.delete();
    await temp.rename(target.path);
    return target.path;
  }

  Future<void> _fetch(
    File temp,
    int resumeFrom,
    void Function(double)? onProgress,
    CancelToken? cancelToken,
  ) async {
    try {
      final response = await _dio.get<ResponseBody>(
        modelUrl,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: resumeFrom > 0 ? {'Range': 'bytes=$resumeFrom-'} : null,
          // 416 = "you already have everything"; we let the hash check decide.
          validateStatus: (s) => s == 200 || s == 206 || s == 416,
        ),
      );

      final status = response.statusCode ?? 0;
      if (status == 416) return;
      final body = response.data;
      if (body == null) throw const ModelSetupException('The server sent an empty file.');

      // 206 = server honoured our Range. 200 = it ignored it and is sending
      // the whole file again, so we must start over (appending would corrupt).
      final resuming = status == 206 && resumeFrom > 0;
      var received = resuming ? resumeFrom : 0;
      final total = _totalBytes(response.headers, status, resumeFrom) ?? expectedSizeBytes;

      final sink = temp.openWrite(mode: resuming ? FileMode.append : FileMode.write);
      var lastPercent = -1;
      try {
        await for (final chunk in body.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (onProgress != null && total > 0) {
            final percent = (received * 100 ~/ total).clamp(0, 100);
            if (percent != lastPercent) {
              // Only tell the screen when the whole number changes (≈100 times
              // instead of thousands), so the UI stays smooth.
              lastPercent = percent;
              onProgress(percent / 100);
            }
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw const ModelSetupException('Download paused. Tap resume to continue.');
      }
      throw ModelSetupException(_friendly(e));
    }
  }

  /// `response.headers` (not `body.headers`) is the one with `.value()`.
  int? _totalBytes(Headers headers, int status, int resumeFrom) {
    final range = headers.value('content-range'); // e.g. "bytes 100-999/1000"
    if (range != null) {
      final slash = range.lastIndexOf('/');
      final total = slash == -1 ? null : int.tryParse(range.substring(slash + 1));
      if (total != null) return total;
    }
    final length = int.tryParse(headers.value('content-length') ?? '');
    if (length == null) return null;
    return status == 206 ? length + resumeFrom : length;
  }

  String _friendly(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return 'No internet connection. Connect and tap resume.';
      case DioExceptionType.receiveTimeout:
        return 'The connection is too slow. Tap resume to try again.';
      default:
        return 'The download stopped. Tap resume to continue.';
    }
  }

  /// Checks the file in small pieces.
  Future<bool> _matchesSha256(File file) async {
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final hash = await sink.hash();
    final hex = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return hex == expectedSha256;
  }

  /// The knowledge database must be a real file (Android opens it by path).
  Future<String> prepareKnowledge() async {
    final file = File(p.join((await _dir()).path, knowledgeFileName));
    if (await file.exists() && await file.length() == knowledgeSizeBytes) {
      return file.path;
    }
    try {
      final data = await rootBundle.load(knowledgeAsset);
      final temp = File('${file.path}.tmp');
      await temp.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
      return file.path;
    } catch (e) {
      throw ModelSetupException(
         'Offline knowledge file could not be prepared: $e\n'
          'Check that pubspec.yaml lists "$knowledgeAsset" under flutter: assets:');
    }
  }

  Future<String> runtimePath() async => p.join((await _dir()).path, runtimeFileName);
}