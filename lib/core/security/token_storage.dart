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

  static const _tokenKey = 'access_token'; // the JWT, lives ~8 hours
  static const _emailKey = 'saved_email'; // used for the silent re-login
  static const _passwordKey = 'saved_password'; // used for the silent re-login
  static const _themeKey = 'theme_mode'; // 'dark' or 'light'
  static const _userIdKey =
      'local_user_id'; // stable id for this phone's offline data
  static const _chatIdKey = 'active_chat_id'; // the conversation currently open

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

  /// Throws away the JWT AND the saved login. This is what "signed out" means.
  Future<void> clearSession() async {
    await _s.delete(key: _tokenKey);
    await _s.delete(key: _emailKey);
    await _s.delete(key: _passwordKey);
  }

  // ---- Theme ----
  Future<String?> readTheme() => _s.read(key: _themeKey);
  Future<void> saveTheme(String mode) => _s.write(key: _themeKey, value: mode);

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
