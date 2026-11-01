import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class ThemeState extends Equatable {
  /// Light (HelpMum light green) is the default, never "empty".
  const ThemeState({this.themeMode = ThemeMode.light});

  final ThemeMode themeMode;

  bool get isDark => themeMode == ThemeMode.dark;

  @override
  List<Object?> get props => [themeMode];
}
