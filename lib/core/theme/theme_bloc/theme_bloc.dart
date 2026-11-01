import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../security/token_storage.dart';
import 'theme_event.dart';
import 'theme_state.dart';

class ThemeBloc extends Bloc<ThemeEvent, ThemeState> {
  /// [initialMode] is read in main() before the first frame so the app never
  /// flashes the wrong theme while storage is being read.
  ThemeBloc(this._storage, {ThemeMode initialMode = ThemeMode.light})
      : super(ThemeState(themeMode: initialMode)) {
    on<ThemeLoaded>(_onLoaded);
    on<ThemeToggled>(_onToggled);
  }

  final TokenStorage _storage;

  static ThemeMode parseMode(String? value) =>
      value == 'dark' ? ThemeMode.dark : ThemeMode.light;

  Future<void> _onLoaded(ThemeLoaded event, Emitter<ThemeState> emit) async {
    try {
      final saved = await _storage.readTheme();
      if (saved == null) return; // nothing saved yet: keep the default
      emit(ThemeState(themeMode: parseMode(saved)));
    } catch (_) {
      // Storage can fail on some devices; the default theme is fine.
    }
  }

  Future<void> _onToggled(ThemeToggled event, Emitter<ThemeState> emit) async {
    final next = state.isDark ? ThemeMode.light : ThemeMode.dark;
    emit(ThemeState(themeMode: next)); // change the screen first...
    try {
      await _storage.saveTheme(next == ThemeMode.dark ? 'dark' : 'light');
    } catch (_) {
      // ...saving is a nice-to-have, so a failure must not undo the change.
    }
  }
}
