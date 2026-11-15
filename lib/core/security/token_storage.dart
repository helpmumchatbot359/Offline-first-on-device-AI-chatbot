import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// The email + password the person typed when they signed in.
/// We keep them in the phone's locked safe ONLY so the app can quietly ask
/// the server for a fresh 8-hour JWT when the old one runs out.
class SavedLogin {
  const SavedLogin({required this.email, required this.password});
  final String email;
  final String password;
}

/// The phone's locked safe. Everything that must stay private lives here.
class TokenStorage {
  // Optional injection of secure storage for testing; defaults to hardware encryption.
  TokenStorage([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  /// Stable local partition key for an account on this phone.
  static String accountOwnerForEmail(String email) =>
      'account:${email.trim().toLowerCase()}';

  static const _tokenKey = 'access_token'; // the JWT, lives ~8 hours
  static const _emailKey = 'saved_email'; // used for the silent re-login
  static const _passwordKey = 'saved_password'; // used for the silent re-login
  static const _themeKey = 'theme_mode'; // 'dark' or 'light'
  static const _userIdKey =
      'local_user_id'; // stable id for this phone's offline data
  static const _chatIdKey = 'active_chat_id'; // the conversation currently open
  static const _profileNameKey = 'profile_name';
  static const _profileEmailKey = 'profile_email';
  static const _chatTitlesKey = 'chat_titles'; // custom names, keyed by chat id
  static const _offlineBannerHiddenKey =
      'offline_banner_hidden'; // "hide for now" on chat

  // ---- Access token (the 8-hour JWT) ----
  Future<String?> readToken() => _s.read(key: _tokenKey);
  Future<void> saveToken(String token) =>
      _s.write(key: _tokenKey, value: token);
  Future<void> clearToken() => _s.delete(key: _tokenKey);

  // ---- Saved login (for silent re-login) ----
  Future<void> saveCredentials({
    required String email,
    required String password,
  }) async {
    await _s.write(key: _emailKey, value: email);
    await _s.write(key: _passwordKey, value: password);
  }

  Future<SavedLogin?> readCredentials() async {
    final email = await _s.read(key: _emailKey);
    final password = await _s.read(key: _passwordKey);
    if (email == null ||
        email.isEmpty ||
        password == null ||
        password.isEmpty) {
      return null;
    }
    return SavedLogin(email: email, password: password);
  }

  Future<void> clearSession() async {
    await _s.delete(key: _tokenKey);
    await _s.delete(key: _emailKey);
    await _s.delete(key: _passwordKey);
    // The friendly name and email are deliberately kept. The server only
    // returns a token on sign-in, so this is the only way to remember the
    // username the person chose. A different account signing in overwrites
    // them (see saveProfileEmail below), so the old name never leaks across
    // accounts.
  }

  /// Removes account identity and the active chat after permanent deletion.
  /// Theme and offline-model preferences belong to this phone, so they remain.
  Future<void> clearAccountData() async {
    await clearSession();
    await _s.delete(key: _userIdKey);
    await _s.delete(key: _chatIdKey);
    await _s.delete(key: _profileNameKey);
    await _s.delete(key: _profileEmailKey);
    await _s.delete(key: _chatTitlesKey);
  }

  // ---- Profile (shown in the drawer and settings) ----
  Future<void> saveProfileName(String name) =>
      _s.write(key: _profileNameKey, value: name.trim());

  Future<String?> readProfileName() => _s.read(key: _profileNameKey);

  /// Remembers the email and forgets a name that belonged to another account.
  Future<void> saveProfileEmail(String email) async {
    final clean = email.trim();
    final previous = await _s.read(key: _profileEmailKey);
    if (previous != null && previous.toLowerCase() != clean.toLowerCase()) {
      await _s.delete(key: _profileNameKey);
    }
    await _s.write(key: _profileEmailKey, value: clean);
  }

  Future<String?> readProfileEmail() => _s.read(key: _profileEmailKey);

  // ---- Custom chat names ----
  Future<Map<String, String>> readChatTitles() async {
    final raw = await _s.read(key: _chatTitlesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
    } catch (_) {
      // A corrupt value must never stop the history list from loading.
    }
    return {};
  }

  Future<void> saveChatTitle(String chatId, String title) async {
    final titles = await readChatTitles();
    titles[chatId] = title;
    await _s.write(key: _chatTitlesKey, value: jsonEncode(titles));
  }

  Future<void> deleteChatTitle(String chatId) async {
    final titles = await readChatTitles();
    if (titles.remove(chatId) == null) return;
    await _s.write(key: _chatTitlesKey, value: jsonEncode(titles));
  }

  // ---- Theme ----
  Future<String?> readTheme() => _s.read(key: _themeKey);
  Future<void> saveTheme(String mode) => _s.write(key: _themeKey, value: mode);

  // ---- Offline download card ("hide for now") ----
  // Saved so that once a person hides the card on the chat screen it stays
  // hidden after the app is restarted. The download itself is unaffected.
  Future<bool> readOfflineBannerHidden() async =>
      (await _s.read(key: _offlineBannerHiddenKey)) == 'true';

  Future<void> saveOfflineBannerHidden(bool hidden) =>
      _s.write(key: _offlineBannerHiddenKey, value: hidden ? 'true' : 'false');

  // ---- Chat identity ----

  /// Same id every time the app opens (the offline engine scopes data by it).
  Future<String> localUserId() => _readOrCreate(_userIdKey, 'local-');

  /// The chat that is open. Survives app restarts so history is not lost.
  Future<String> activeChatId() => _readOrCreate(_chatIdKey, 'user-');

  /// NEW CHAT: hands out a brand-new chat id and remembers it.
  /// The old chat is NOT deleted; it simply stops being the "open" one.
  Future<String> startNewChat() async {
    final id = 'user-${const Uuid().v4()}';
    await _s.write(key: _chatIdKey, value: id);
    return id;
  }

  /// Re-opens a conversation from the history list.
  Future<void> setActiveChat(String chatId) =>
      _s.write(key: _chatIdKey, value: chatId);

  /// Forget the open chat (used on sign out so the next person starts fresh).
  Future<void> resetChatSession() => _s.delete(key: _chatIdKey);

  Future<String> _readOrCreate(String key, String prefix) async {
    final existing = await _s.read(key: key);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = '$prefix${const Uuid().v4()}';
    await _s.write(key: key, value: created);
    return created;
  }
}
