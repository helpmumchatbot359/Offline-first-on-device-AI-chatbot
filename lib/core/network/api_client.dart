import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../config/env.dart';
import '../security/token_storage.dart';

enum RefreshResult {
  refreshed, // got a brand-new JWT
  rejected, // server said "that email/password is no longer valid"
  unreachable, // no internet / server down: we do NOT know, so do NOT sign out
}

class ApiClient {
  ApiClient(this._tokenStorage)
      : dio = Dio(BaseOptions(
          baseUrl: Env.baseUrl,
          // Slow mobile networks need more patience than 10s to connect.
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'X-API-KEY': Env.apiKey,
            'Content-Type': 'application/json',
          },
        )),
        // A second, plain Dio with NO interceptors. It is used only for the
        // silent login so it can never trigger itself in an endless loop.
        _loginDio = Dio(BaseOptions(
          baseUrl: Env.baseUrl,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
          headers: {
            'X-API-KEY': Env.apiKey,
            'Content-Type': 'application/json',
          },
        )) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: _attachToken,
      onError: _renewSessionAndRetry,
    ));
  }

  final TokenStorage _tokenStorage;
  final Dio dio;
  final Dio _loginDio;

  static const _publicPaths = {
    '/user/login',
    '/user/signup',
  };
  static bool _isPublic(String path) => _publicPaths.contains(path);

  final _expiredController = StreamController<void>.broadcast();

  /// Fires ONLY when the server really refuses our saved email/password
  /// (for example the password was changed). Then the person must sign in.
  Stream<void> get sessionExpired => _expiredController.stream;

  /// True if somebody is signed in on this phone.
  Future<bool> isSignedIn() async {
    final token = await _tokenStorage.readToken();
    if (token != null && token.isNotEmpty) return true;
    return (await _tokenStorage.readCredentials()) != null;
  }

  // ---------------------------------------------------------------------------
  // BEFORE every private request: make sure the JWT is fresh.
  // ---------------------------------------------------------------------------
  Future<void> _attachToken(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isPublic(options.path)) {
      var token = await _tokenStorage.readToken();

      // Missing, expired, or expiring within 2 minutes? Get a new one first.
      if (token == null || token.isEmpty || _expiresSoon(token)) {
        final result = await refreshSession();
        if (result == RefreshResult.refreshed) {
          token = await _tokenStorage.readToken();
        }
        // If "unreachable" we keep the old token and let the request try.
      }

      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  // ---------------------------------------------------------------------------
  // AFTER a request fails with 401: get a new JWT and try ONE more time.
  // ---------------------------------------------------------------------------
  Future<void> _renewSessionAndRetry(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final request = err.requestOptions;
    final isExpiredLogin = err.response?.statusCode == 401;
    final alreadyRetried = request.extra['retried'] == true;

    if (!isExpiredLogin || _isPublic(request.path) || alreadyRetried) {
      return handler.next(err);
    }

    final result = await refreshSession();
    if (result != RefreshResult.refreshed) {
      return handler.next(err);
    }

    try {
      request.extra['retried'] = true;
      final newToken = await _tokenStorage.readToken();
      if (newToken != null && newToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $newToken';
      }
      final retryResponse = await dio.fetch(request);
      return handler.resolve(retryResponse);
    } on DioException catch (retryError) {
      return handler.next(retryError);
    }
  }

  // If 5 requests all notice the expired JWT at the same moment, only ONE
  // silent login happens and the other 4 wait for its result.
  Future<RefreshResult>? _refreshing;

  Future<RefreshResult> refreshSession() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<RefreshResult> _doRefresh() async {
    final saved = await _tokenStorage.readCredentials();

    if (saved == null) {
      // Nothing to log in with. If a (probably expired) token is still
      // sitting there, the person has to sign in again.
      final token = await _tokenStorage.readToken();
      if (token != null && token.isNotEmpty) await _expireSession();
      return RefreshResult.rejected;
    }

    try {
      final response = await _loginDio.post('/user/login', data: {
        'email': saved.email,
        'password': saved.password,
      });
      final data = response.data;
      final newAccess = data is Map ? data['access_token'] : null;
      if (newAccess is! String || newAccess.isEmpty) {
        return RefreshResult.unreachable; // odd reply: do not sign out
      }
      await _tokenStorage.saveToken(newAccess);
      return RefreshResult.refreshed;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      // ONLY "wrong email or password" means the login is really over.
      // (403 is left out on purpose: a missing API key also gives 403, and
      //  that must never sign everybody out.)
      if (code == 400 || code == 401) {
        await _expireSession();
        return RefreshResult.rejected;
      }
      // No internet, timeout, server error: we simply could not check.
      return RefreshResult.unreachable;
    }
  }

  Future<void> _expireSession() async {
    await _tokenStorage.clearSession();
    if (!_expiredController.isClosed) _expiredController.add(null);
  }

  /// Reads the "exp" (expiry) time hidden inside the JWT.
  /// If anything looks odd we return false and let the server decide.
  static bool _expiresSoon(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return false;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final exp = (jsonDecode(payload) as Map)['exp'];
      if (exp is! num) return false;
      final expiry = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
      return DateTime.now().toUtc().isAfter(expiry.subtract(const Duration(minutes: 2)));
    } catch (_) {
      return false;
    }
  }
}