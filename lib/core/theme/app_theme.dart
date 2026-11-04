import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// HelpMum Africa brand colours. The whole palette is built around
/// spring green (#00FA9A), so every shade below is a darker or lighter
/// version of that same hue.
class MamaColors {
  MamaColors._();

  /// The anchor colour the rest of the palette is derived from.
  static const springGreen = Color(0xFF00FA9A);

  static const brandGreen = Color(0xFF007A55); // buttons, user bubble (light)
  static const brandLightGreen = Color(
    0xFFC9FFE6,
  ); // app bar, soft surfaces (light)
  static const brandMint = springGreen; // primary on dark backgrounds
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

/// Extra colours used by the "pretty" screens (onboarding, empty states).
/// Keeping them here means light mode and dark mode always change together.
@immutable
class MamaSurfaceColors extends ThemeExtension<MamaSurfaceColors> {
  const MamaSurfaceColors({
    required this.backgroundGradient,
    required this.aurora,
    required this.ctaGradient,
    required this.onCta,
    required this.glassFill,
    required this.glassBorder,
  });

  /// Top-to-bottom colour wash used behind the onboarding slides.
  final List<Color> backgroundGradient;

  /// Soft moving light blobs. Three or four colours, drawn as glowing circles.
  final List<Color> aurora;

  /// The two colours of the main call-to-action button.
  final List<Color> ctaGradient;
  final Color onCta;

  /// Frosted "glass" look for the icon circle and other floating panels.
  final Color glassFill;
  final Color glassBorder;

  @override
  MamaSurfaceColors copyWith({
    List<Color>? backgroundGradient,
    List<Color>? aurora,
    List<Color>? ctaGradient,
    Color? onCta,
    Color? glassFill,
    Color? glassBorder,
  }) {
    return MamaSurfaceColors(
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
      aurora: aurora ?? this.aurora,
      ctaGradient: ctaGradient ?? this.ctaGradient,
      onCta: onCta ?? this.onCta,
      glassFill: glassFill ?? this.glassFill,
      glassBorder: glassBorder ?? this.glassBorder,
    );
  }

  @override
  MamaSurfaceColors lerp(ThemeExtension<MamaSurfaceColors>? other, double t) {
    if (other is! MamaSurfaceColors) return this;

    List<Color> mixList(List<Color> a, List<Color> b) {
      final length = a.length < b.length ? a.length : b.length;
      return List<Color>.generate(length, (i) => Color.lerp(a[i], b[i], t)!);
    }

    return MamaSurfaceColors(
      backgroundGradient: mixList(backgroundGradient, other.backgroundGradient),
      aurora: mixList(aurora, other.aurora),
      ctaGradient: mixList(ctaGradient, other.ctaGradient),
      onCta: Color.lerp(onCta, other.onCta, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
    );
  }
}

extension MamaThemeContext on BuildContext {
  MamaChatColors get chatColors => Theme.of(this).extension<MamaChatColors>()!;
  MamaSurfaceColors get brandColors =>
      Theme.of(this).extension<MamaSurfaceColors>()!;
}

class AppTheme {
  AppTheme._();

  // `static final` = built once, not on every rebuild.
  static final ThemeData light = _build(
    scaffold: const Color(0xFFF6FFFA),
    scheme: const ColorScheme(
      brightness: Brightness.light,
      primary: MamaColors.brandGreen,
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: MamaColors.brandLightGreen,
      onPrimaryContainer: Color(0xFF003826),
      secondary: Color(0xFF00795C),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFD6FFF0),
      onSecondaryContainer: Color(0xFF00332A),
      tertiary: Color(0xFF8A5200),
      onTertiary: Color(0xFFFFFFFF),
      error: Color(0xFFB3261E),
      onError: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF0E211A),
      onSurfaceVariant: Color(0xFF43564D),
      outline: Color(0xFF7FA99A),
      outlineVariant: Color(0xFFCDEBDD),
    ),
    chat: const MamaChatColors(
      userBubble: MamaColors.brandGreen,
      onUserBubble: Color(0xFFFFFFFF),
      aiBubble: Color(0xFFFFFFFF),
      onAiBubble: Color(0xFF0E211A),
      aiBubbleBorder: Color(0xFFCDEBDD),
      meta: Color(0xFF557064),
      offlineBadge: Color(0xFFFFF1D6),
      onOfflineBadge: Color(0xFF7A4800),
      errorBubble: Color(0xFFFDECEA),
      onErrorBubble: Color(0xFF8C1D18),
      online: MamaColors.brandGreen,
      offline: Color(0xFFB26A00),
    ),
    brand: const MamaSurfaceColors(
      // Near-white at the top, ripening into a soft spring-green at the
      // bottom - the same top-to-bottom flow as Gemini, in our palette.
      backgroundGradient: [
        Color(0xFFFBFFFD),
        Color(0xFFEAFFF5),
        Color(0xFFA9FFD4),
      ],
      aurora: [
        Color(0xFF00FA9A),
        Color(0xFF7CFFC4),
        Color(0xFF00D68F),
      ],
      ctaGradient: [Color(0xFF006B4A), Color(0xFF00805A)],
      onCta: Color(0xFFFFFFFF),
      glassFill: Color(0xB8FFFFFF),
      glassBorder: Color(0xFFC2EEDD),
    ),
  );

  // The dark palette starts at true black at the top of the screen and lets a
  // spring-green glow pool at the bottom. The black keeps every green surface
  // and bubble crisp instead of turning the screen into green-grey mush.
  static final ThemeData dark = _build(
    scaffold: const Color(0xFF000000),
    scheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: MamaColors.springGreen,
      onPrimary: Color(0xFF00281A),
      primaryContainer: Color(0xFF0C3A29),
      onPrimaryContainer: Color(0xFF9CFFD2),
      secondary: Color(0xFF7CFFC4),
      onSecondary: Color(0xFF00281A),
      secondaryContainer: Color(0xFF12402F),
      onSecondaryContainer: Color(0xFFC9FFE6),
      tertiary: Color(0xFFF5C77E),
      onTertiary: Color(0xFF3D2800),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      surface: Color(0xFF06100C),
      onSurface: Color(0xFFE4FFF2),
      onSurfaceVariant: Color(0xFF9CB8AC),
      outline: Color(0xFF4F7A6A),
      outlineVariant: Color(0xFF163127),
    ),
    chat: const MamaChatColors(
      userBubble: MamaColors.springGreen,
      onUserBubble: Color(0xFF00281A),
      aiBubble: Color(0xFF071310),
      onAiBubble: Color(0xFFE4FFF2),
      aiBubbleBorder: Color(0xFF143327),
      meta: Color(0xFF8FAFA1),
      offlineBadge: Color(0xFF3A2C0F),
      onOfflineBadge: Color(0xFFFFD08A),
      errorBubble: Color(0xFF3A1918),
      onErrorBubble: Color(0xFFFFB4AB),
      // The status dot sits on the spring-green header in dark mode, so it
      // needs a dark ink to stay visible (it is light on the light header).
      online: Color(0xFF00281A),
      offline: Color(0xFF6B3F00),
    ),
    brand: const MamaSurfaceColors(
      // True black up top, then a green pool of light at the bottom edge.
      backgroundGradient: [
        Color(0xFF000000),
        Color(0xFF01120B),
        Color(0xFF004D30),
      ],
      aurora: [
        Color(0xFF00FA9A),
        Color(0xFF7CFFC4),
        Color(0xFF00C97B),
        Color(0xFF5CFFC0),
      ],
      ctaGradient: [Color(0xFF00FA9A), Color(0xFF7CFFC4)],
      onCta: Color(0xFF00281A),
      glassFill: Color(0x14FFFFFF),
      glassBorder: Color(0x2EFFFFFF),
    ),
  );

  static ThemeData _build({
    required ColorScheme scheme,
    required MamaChatColors chat,
    required MamaSurfaceColors brand,
    required Color scaffold,
  }) {
    final isDark = scheme.brightness == Brightness.dark;
    // Both headers are light surfaces now: the dark theme uses the same
    // spring green as the question ribbon, so the status-bar icons must be
    // dark in both themes. Screens without an app bar (onboarding) override
    // this with their own AnnotatedRegion.
    const overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    const buttonSize = Size(48, 52);

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      extensions: <ThemeExtension<dynamic>>[chat, brand],
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
        ),
      ),
      appBarTheme: AppBarTheme(
        // Light mode keeps the soft spring-green bar. Dark mode uses the
        // exact spring green of the user's question bubble, with the same
        // dark ink, so the header feels as vivid as the chat ribbon.
        backgroundColor: isDark ? scheme.primary : scheme.primaryContainer,
        foregroundColor: isDark ? scheme.onPrimary : scheme.onPrimaryContainer,
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 12,
        ),
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
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
