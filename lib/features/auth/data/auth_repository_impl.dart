import 'dart:async';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/token_storage.dart';
import '../domain/auth_repository.dart';
import '../domain/user_profile.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._apiClient, this._tokenStorage);
  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

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
