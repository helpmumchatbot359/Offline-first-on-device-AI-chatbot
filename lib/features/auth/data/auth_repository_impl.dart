import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/token_storage.dart';
import '../domain/auth_repository.dart';
import '../domain/user_profile.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(
    this._apiClient,
    this._tokenStorage, {
    this._clearLocalAccountData,
    this._setLocalAccountOwner,
  });
  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;
  final Future<void> Function()? _clearLocalAccountData;
  final Future<void> Function(String ownerId)? _setLocalAccountOwner;

  @override
  Stream<void> get sessionExpired => _apiClient.sessionExpired;

  /// Signed in = we hold a JWT OR we hold the saved login that can make one.
  /// An old JWT does NOT matter: the ApiClient swaps it quietly.
  @override
  Future<bool> hasSession() => _apiClient.isSignedIn();

  @override
  Future<UserProfile?> currentUser() async {
    final savedEmail = await _tokenStorage.readProfileEmail();
    final login = await _tokenStorage.readCredentials();
    final email = savedEmail ?? login?.email;
    if (email == null || email.trim().isEmpty) return null;

    final savedName = await _tokenStorage.readProfileName();
    final name = (savedName != null && savedName.trim().isNotEmpty)
        ? savedName.trim()
        : _nameFromEmail(email);
    return UserProfile(name: name, email: email.trim());
  }

  @override
  Future<void> signUp({
    required String username,
    required String gender,
    required String email,
    required String country,
    required String password,
  }) async {
    try {
      await _apiClient.dio.post(
        '/user/signup',
        data: {
          'username': username,
          'gender': gender,
          'email': email,
          'country': country,
          'password': password,
        },
      );
      // Keep the friendly name on this phone so the account feels personal
      // as soon as the person signs in.
      await _tokenStorage.saveProfileEmail(email);
      await _tokenStorage.saveProfileName(username);
    } on DioException catch (e) {
      throw AuthException(_messageFrom(e, 'Sign up failed. Please try again.'));
    }
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      final response = await _apiClient.dio.post(
        '/user/login',
        data: {'email': email, 'password': password},
      );

      final data = response.data;
      final accessToken = data is Map ? data['access_token'] : null;

      if (accessToken is! String || accessToken.isEmpty) {
        throw AuthException('The server did not return an access token.');
      }
      await _setLocalAccountOwner?.call(
        TokenStorage.accountOwnerForEmail(email),
      );
      // A sign-in starts with a fresh blank conversation. Existing chats stay
      // in the account's history instead of remaining the active chat.
      await _tokenStorage.resetChatSession();
      await _tokenStorage.saveToken(accessToken);
      // Keep the login in the locked safe so we can renew the 8-hour JWT silently.
      await _tokenStorage.saveCredentials(email: email, password: password);
      await _tokenStorage.saveProfileEmail(email);
    } on DioException catch (e) {
      throw AuthException(_messageFrom(e, 'Sign in failed. Please try again.'));
    }
  }

  /// The ONLY normal way to lose the login: the person taps "Sign out".
  @override
  Future<void> signOut() async {
    await _tokenStorage.clearSession(); // JWT + saved email/password
    await _tokenStorage.resetChatSession();
  }

  @override
  Future<void> deleteAccount() async {
    var token = await _tokenStorage.readToken();

    // A missing JWT does not always mean the person is signed out. The app
    // keeps the saved login securely so ApiClient can quietly get another JWT.
    // Ask it to do that before we decide the person must sign in again.
    if (token == null || token.isEmpty) {
      final refreshResult = await _apiClient.refreshSession();
      token = await _tokenStorage.readToken();

      // If the network is down, keep the saved login and let the person retry.
      // If the server rejected the saved login (or there was no saved login),
      // use the same sign-in-again message as the rest of the app.
      if (token == null || token.isEmpty) {
        if (refreshResult == RefreshResult.unreachable) {
          throw AuthException(
            'Could not reconnect to your account. Check your internet and try again.',
          );
        }
        throw AuthException(
          'Please sign in again before deleting your account.',
        );
      }
    }
    final appUserId = _appUserIdFromToken(token);

    try {
      // The current backend route still expects the account ID in the path.
      // ApiClient attaches the JWT and handles its normal refresh/retry flow.
      await _apiClient.dio.delete<dynamic>(
        '/user/${Uri.encodeComponent(appUserId)}',
      );
    } on DioException catch (e) {
      throw AuthException(
        _messageFrom(e, 'Could not delete your account. Please try again.'),
      );
    }

    // Only erase local conversations after the server confirms deletion.
    try {
      await _clearLocalAccountData?.call();
    } finally {
      await _tokenStorage.clearAccountData();
    }
  }

  /// Reads the numeric account ID from the JWT's `sub` claim for the current
  /// backend route. The server must still validate the JWT and authorize that
  /// the path ID belongs to it; client-side decoding is not verification.
  static String _appUserIdFromToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw AuthException(
        'Could not read your account ID. Please sign in again.',
      );
    }

    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final subject = payload is Map ? payload['sub']?.toString().trim() : null;
      if (subject == null || !RegExp(r'^\d+$').hasMatch(subject)) {
        throw AuthException(
          'Could not read your account ID. Please sign in again.',
        );
      }
      return subject;
    } on AuthException {
      rethrow;
    } catch (_) {
      throw AuthException(
        'Could not read your account ID. Please sign in again.',
      );
    }
  }

  /// Turns `ada.lovelace+mother@example.com` into `Ada Lovelace Mother`.
  /// Used only when an existing account signs in on a new phone.
  static String _nameFromEmail(String email) {
    final local = email.split('@').first;
    final words = local
        .split(RegExp(r'[._\-+]+'))
        .where((word) => word.trim().isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .toList();
    return words.isEmpty ? 'Mama' : words.join(' ');
  }

  static String _messageFrom(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map) {
      final m = data['message'] ?? data['detail'];
      if (m is String && m.trim().isNotEmpty) return m;
      if (m is List && m.isNotEmpty) return m.first.toString();
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The server took too long to answer. Please try again.';
      case DioExceptionType.connectionError:
        return 'Could not reach the server. Check your internet and try again.';
      default:
        return fallback;
    }
  }
}
