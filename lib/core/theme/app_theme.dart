import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// HelpMum Africa brand colours. Light green is the identity of the app,
/// so it is used for the app bar, bubbles and buttons in both modes.
class MamaColors {
  MamaColors._();
  static const brandGreen = Color(0xFF277A42); // buttons, user bubble (light)
  static const brandLightGreen = Color(0xFFCDEFC9); // app bar, soft surfaces (light)
  static const brandMint = Color(0xFF8FD99A); // primary on dark backgrounds
}

/// Extra colours for the chat screen that Material's ColorScheme has no slot for.
@immutable
class MamaChatColors extends ThemeExtension<MamaChatColors> {
  const MamaChatColors({
    required this.userBubble,
    required this.onUserBubble,
    required this.aiBubble,
    required this.onAiBubble,
    required this.aiBubbleBorder,
    required this.meta,
    required this.offlineBadge,
    required this.onOfflineBadge,
    required this.errorBubble,
    required this.onErrorBubble,
    required this.online,
    required this.offline,
  });

  final Color userBubble;
  final Color onUserBubble;
  final Color aiBubble;
  final Color onAiBubble;
  final Color aiBubbleBorder;
  final Color meta;
  final Color offlineBadge;
  final Color onOfflineBadge;
  final Color errorBubble;
  final Color onErrorBubble;
  final Color online;
  final Color offline;

  @override
  MamaChatColors copyWith({
    Color? userBubble,
    Color? onUserBubble,
    Color? aiBubble,
    Color? onAiBubble,
    Color? aiBubbleBorder,
    Color? meta,
    Color? offlineBadge,
    Color? onOfflineBadge,
    Color? errorBubble,
    Color? onErrorBubble,
    Color? online,
    Color? offline,
  }) {
    return MamaChatColors(
      userBubble: userBubble ?? this.userBubble,
      onUserBubble: onUserBubble ?? this.onUserBubble,
      aiBubble: aiBubble ?? this.aiBubble,
      onAiBubble: onAiBubble ?? this.onAiBubble,
      aiBubbleBorder: aiBubbleBorder ?? this.aiBubbleBorder,
      meta: meta ?? this.meta,
      offlineBadge: offlineBadge ?? this.offlineBadge,
      onOfflineBadge: onOfflineBadge ?? this.onOfflineBadge,
      errorBubble: errorBubble ?? this.errorBubble,
      onErrorBubble: onErrorBubble ?? this.onErrorBubble,
      online: online ?? this.online,
      offline: offline ?? this.offline,
    );
  }

  @override
  MamaChatColors lerp(ThemeExtension<MamaChatColors>? other, double t) {
    if (other is! MamaChatColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return MamaChatColors(
      userBubble: mix(userBubble, other.userBubble),
      onUserBubble: mix(onUserBubble, other.onUserBubble),
      aiBubble: mix(aiBubble, other.aiBubble),
      onAiBubble: mix(onAiBubble, other.onAiBubble),
      aiBubbleBorder: mix(aiBubbleBorder, other.aiBubbleBorder),
      meta: mix(meta, other.meta),
      offlineBadge: mix(offlineBadge, other.offlineBadge),
      onOfflineBadge: mix(onOfflineBadge, other.onOfflineBadge),
      errorBubble: mix(errorBubble, other.errorBubble),
      onErrorBubble: mix(onErrorBubble, other.onErrorBubble),
      online: mix(online, other.online),
      offline: mix(offline, other.offline),
    );
  }
}

extension MamaThemeContext on BuildContext {
  MamaChatColors get chatColors => Theme.of(this).extension<MamaChatColors>()!;
}

class AppTheme {
  AppTheme._();

  // `static final` = built once, not on every rebuild.
  static final ThemeData light = _build(
    scaffold: const Color(0xFFF2F9EE),
    scheme: const ColorScheme(
      brightness: Brightness.light,
      primary: MamaColors.brandGreen,
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: MamaColors.brandLightGreen,
      onPrimaryContainer: Color(0xFF0B3A1B),
      secondary: Color(0xFF4F7A57),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFDDEFD9),
      onSecondaryContainer: Color(0xFF12301A),
      tertiary: Color(0xFF8A5200),
      onTertiary: Color(0xFFFFFFFF),
      error: Color(0xFFB3261E),
      onError: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF15231A),
      onSurfaceVariant: Color(0xFF4A5B4E),
      outline: Color(0xFF8DA391),
      outlineVariant: Color(0xFFD2E3D0),
    ),
    chat: const MamaChatColors(
      userBubble: MamaColors.brandGreen,
      onUserBubble: Color(0xFFFFFFFF),
      aiBubble: Color(0xFFFFFFFF),
      onAiBubble: Color(0xFF15231A),
      aiBubbleBorder: Color(0xFFD2E3D0),
      meta: Color(0xFF5B6D5F),
      offlineBadge: Color(0xFFFFF1D6),
      onOfflineBadge: Color(0xFF7A4800),
      errorBubble: Color(0xFFFDECEA),
      onErrorBubble: Color(0xFF8C1D18),
      online: MamaColors.brandGreen,
      offline: Color(0xFFB26A00),
    ),
  );

  static final ThemeData dark = _build(
    scaffold: const Color(0xFF0C140F),
    scheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: MamaColors.brandMint,
      onPrimary: Color(0xFF05290F),
      primaryContainer: Color(0xFF1F5A33),
      onPrimaryContainer: Color(0xFFCDEFC9),
      secondary: Color(0xFFA5CFA9),
      onSecondary: Color(0xFF0E2A16),
      secondaryContainer: Color(0xFF2B4A33),
      onSecondaryContainer: Color(0xFFDDEFD9),
      tertiary: Color(0xFFFFC670),
      onTertiary: Color(0xFF442900),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      surface: Color(0xFF121C15),
      onSurface: Color(0xFFE3EEE4),
      onSurfaceVariant: Color(0xFFA9BCAD),
      outline: Color(0xFF6B8271),
      outlineVariant: Color(0xFF26382C),
    ),
    chat: const MamaChatColors(
      userBubble: Color(0xFF2D6B40),
      onUserBubble: Color(0xFFFFFFFF),
      aiBubble: Color(0xFF1B2B20),
      onAiBubble: Color(0xFFE3EEE4),
      aiBubbleBorder: Color(0xFF26382C),
      meta: Color(0xFF9DB2A2),
      offlineBadge: Color(0xFF3A2D10),
      onOfflineBadge: Color(0xFFFFC670),
      errorBubble: Color(0xFF3B1A18),
      onErrorBubble: Color(0xFFFFB4AB),
      online: MamaColors.brandMint,
      offline: Color(0xFFFFC670),
    ),
  );

  static ThemeData _build({
    required ColorScheme scheme,
    required MamaChatColors chat,
    required Color scaffold,
  }) {
    final isDark = scheme.brightness == Brightness.dark;
    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    );
    final buttonShape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    const buttonSize = Size(48, 52);

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      extensions: <ThemeExtension<dynamic>>[chat],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlay,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: buttonSize,
          shape: buttonShape,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          side: BorderSide(color: scheme.outline),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      snackBarTheme:
          const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
