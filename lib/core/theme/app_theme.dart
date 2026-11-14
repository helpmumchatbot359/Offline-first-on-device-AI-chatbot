import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// HelpMum Africa brand colours.
///
/// The golden rule for this palette is: **green is an accent, not a
/// background**. Most of the screen should be neutral (white, grey or
/// charcoal), exactly like WhatsApp and Gemini. Green is then reserved for
/// the few places that need to pull the eye: the send button, the online dot,
/// the selected chat, the primary call-to-action and the user's own bubble.
///
/// Why? A fully green screen forces the eye to work hard, because every
/// surface competes for attention. Neutral surfaces let the green "pop" and
/// make the app feel calm and professional.
class MamaColors {
  MamaColors._();

  /// The original spring green. Kept for reference/backwards compatibility.
  /// It is deliberately NOT used as a large surface any more because it is
  /// very bright (neon) and tiring to look at for long.
  static const springGreen = Color(0xFF00FA9A);

  /// Deep, calm brand green used for buttons and the light-mode user bubble.
  static const brandGreen = Color(0xFF0B7A55);

  /// Softer mint used as the accent on dark surfaces. It is easy on the eyes
  /// but still clearly "MamaBot green".
  static const brandMint = Color(0xFF34D399);

  /// Very light mint wash for subtle tinted surfaces in light mode.
  static const brandLightGreen = Color(0xFFE4F6EE);

  /// A darker green for the dark-mode user bubble. White text sits on it
  /// comfortably, but it does not glow like the old #00FA9A bubble.
  static const deepGreen = Color(0xFF156B4E);

  /// Cool grey-blue used for a very faint background glow. It stops the
  /// background from becoming "green everywhere" and adds depth instead.
  static const slateGlow = Color(0xFF94A3B8);

  /// A darker version of [slateGlow] for the dark theme.
  static const slateGlowDark = Color(0xFF3A5568);

  /// Warm berry accent used on the sign-in / sign-up screen. Green is the
  /// page background there, so the primary actions use its opposite hue to
  /// stop the screen becoming "green on green".
  static const berry = Color(0xFF8E3B5E);
  static const berryDeep = Color(0xFF6E2A47);
}

/// The deep emerald "welcome" palette.
///
/// Onboarding and the auth screen are the only two places where green becomes
/// the whole page instead of just an accent. This is a [ThemeExtension] so
/// Material's built-in theme animation can *blend* these colours instead of
/// snapping between light and dark. That is what removes the flash when the
/// person taps the sun/moon button on those screens.
@immutable
class MamaHeroColors extends ThemeExtension<MamaHeroColors> {
  const MamaHeroColors({
    required this.isDark,
    // The colours are optional so `MamaHeroColors(isDark: ...)` is still
    // valid: it picks the matching light or dark palette automatically.
    Color? top,
    Color? mid,
    Color? bottom,
    Color? glow,
    Color? glow2,
  }) : top = top ?? (isDark ? _darkTop : _lightTop),
       mid = mid ?? (isDark ? _darkMid : _lightMid),
       bottom = bottom ?? (isDark ? _darkBottom : _lightBottom),
       glow = glow ?? (isDark ? _darkGlow : _lightGlow),
       glow2 = glow2 ?? (isDark ? _darkGlow2 : _lightGlow2);

  final bool isDark;
  final Color top;
  final Color mid;
  final Color bottom;
  final Color glow;
  final Color glow2;

  static const _lightTop = Color(0xFF0B8A63);
  static const _lightMid = Color(0xFF066147);
  static const _lightBottom = Color(0xFF023726);
  static const _lightGlow = Color(0xFF7BF7C7);
  static const _lightGlow2 = Color(0xFF34D399);
  static const _darkTop = Color(0xFF064C36);
  static const _darkMid = Color(0xFF032D21);
  static const _darkBottom = Color(0xFF01150E);
  static const _darkGlow = Color(0xFF1FC98D);
  static const _darkGlow2 = Color(0xFF0B8C65);

  static const light = MamaHeroColors(isDark: false);

  static const dark = MamaHeroColors(isDark: true);

  @override
  MamaHeroColors copyWith({
    bool? isDark,
    Color? top,
    Color? mid,
    Color? bottom,
    Color? glow,
    Color? glow2,
  }) {
    return MamaHeroColors(
      isDark: isDark ?? this.isDark,
      top: top ?? this.top,
      mid: mid ?? this.mid,
      bottom: bottom ?? this.bottom,
      glow: glow ?? this.glow,
      glow2: glow2 ?? this.glow2,
    );
  }

  @override
  MamaHeroColors lerp(ThemeExtension<MamaHeroColors>? other, double t) {
    if (other is! MamaHeroColors) return this;
    return MamaHeroColors(
      // A single switch at the midpoint, while every colour blends smoothly.
      isDark: t < 0.5 ? isDark : other.isDark,
      top: Color.lerp(top, other.top, t)!,
      mid: Color.lerp(mid, other.mid, t)!,
      bottom: Color.lerp(bottom, other.bottom, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      glow2: Color.lerp(glow2, other.glow2, t)!,
    );
  }
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

  /// Top-to-bottom colour wash used behind the onboarding slides and chat.
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
  MamaHeroColors get heroColors =>
      Theme.of(this).extension<MamaHeroColors>()!;
}

class AppTheme {
  AppTheme._();

  // `static final` = built once, not on every rebuild.
  static final ThemeData light = _build(
    // A soft, paper-like grey-green instead of near-white. Pure white on a
    // phone screen is tiring to look at, especially on the Settings page.
    scaffold: const Color(0xFFEDF1ED),
    scheme: const ColorScheme(
      brightness: Brightness.light,
      primary: MamaColors.brandGreen,
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: MamaColors.brandLightGreen,
      onPrimaryContainer: Color(0xFF06402D),
      secondary: Color(0xFF0F766E),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFE7F1EF),
      onSecondaryContainer: Color(0xFF0A3B36),
      tertiary: Color(0xFF8A5A00),
      onTertiary: Color(0xFFFFFFFF),
      error: Color(0xFFB3261E),
      onError: Color(0xFFFFFFFF),
      surface: Color(0xFFF9FBF8),
      onSurface: Color(0xFF1A1C1B),
      onSurfaceVariant: Color(0xFF565F59),
      outline: Color(0xFF7D8680),
      outlineVariant: Color(0xFFD9E2DB),
      surfaceTint: Color(0x00000000),
      surfaceContainerLowest: Color(0xFFFDFEFC),
      surfaceContainerLow: Color(0xFFF3F7F3),
      surfaceContainer: Color(0xFFE9EFEA),
      surfaceContainerHigh: Color(0xFFE0E7E1),
      surfaceContainerHighest: Color(0xFFD7DFD8),
      inverseSurface: Color(0xFF2F3130),
      onInverseSurface: Color(0xFFF2F4F3),
      inversePrimary: Color(0xFF7DD3B8),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
    ),
    chat: const MamaChatColors(
      userBubble: MamaColors.brandGreen,
      onUserBubble: Color(0xFFFFFFFF),
      aiBubble: Color(0xFFFBFCFA),
      onAiBubble: Color(0xFF1A1C1B),
      aiBubbleBorder: Color(0xFFD9E2DB),
      meta: Color(0xFF6B7370),
      offlineBadge: Color(0xFFFFF4DE),
      onOfflineBadge: Color(0xFF7A4A00),
      errorBubble: Color(0xFFFDECEA),
      onErrorBubble: Color(0xFF8C1D18),
      online: MamaColors.brandGreen,
      offline: Color(0xFFB26A00),
    ),
    brand: const MamaSurfaceColors(
      // A calm, slightly grey-green wash. It stays clearly lighter than the
      // text but never becomes the harsh near-white it used to be.
      backgroundGradient: [
        Color(0xFFEDF1ED),
        Color(0xFFE9F0EA),
        Color(0xFFE2ECE6),
        Color(0xFFDBE7E1),
      ],
      aurora: [Color(0xFF34D399), Color(0xFF2DD4BF), MamaColors.slateGlow],
      ctaGradient: [Color(0xFF0B7A55), Color(0xFF0F805C)],
      onCta: Color(0xFFFFFFFF),
      glassFill: Color(0xB8FFFFFF),
      glassBorder: Color(0xFFD5E4DC),
    ),
  );

  // Dark mode is built from neutral charcoal, not green. The greys below are
  // very close to Gemini's dark surfaces, which keeps text comfortable and
  // lets the small green accents stand out.
  static final ThemeData dark = _build(
    scaffold: const Color(0xFF0E0F0F),
    scheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: MamaColors.brandMint,
      onPrimary: Color(0xFF052E1F),
      primaryContainer: Color(0xFF123A2C),
      onPrimaryContainer: Color(0xFFB7F7D8),
      secondary: Color(0xFF7DD3B8),
      onSecondary: Color(0xFF04251C),
      secondaryContainer: Color(0xFF1B2B25),
      onSecondaryContainer: Color(0xFFD4EDE2),
      tertiary: Color(0xFFE7C27D),
      onTertiary: Color(0xFF2B1D00),
      error: Color(0xFFF2B8B5),
      onError: Color(0xFF601410),
      surface: Color(0xFF131314),
      onSurface: Color(0xFFE6E6E6),
      onSurfaceVariant: Color(0xFFA8ADAA),
      outline: Color(0xFF6A706D),
      outlineVariant: Color(0xFF2B2E2C),
      surfaceTint: Color(0x00000000),
      surfaceContainerLowest: Color(0xFF0B0C0C),
      surfaceContainerLow: Color(0xFF161718),
      surfaceContainer: Color(0xFF1B1C1D),
      surfaceContainerHigh: Color(0xFF232425),
      surfaceContainerHighest: Color(0xFF2C2D2E),
      inverseSurface: Color(0xFFE6E6E6),
      onInverseSurface: Color(0xFF131314),
      inversePrimary: Color(0xFF0B7A55),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
    ),
    chat: const MamaChatColors(
      userBubble: MamaColors.deepGreen,
      onUserBubble: Color(0xFFE8FFF5),
      aiBubble: Color(0xFF1B1C1D),
      onAiBubble: Color(0xFFE6E6E6),
      aiBubbleBorder: Color(0xFF2B2E2C),
      meta: Color(0xFF9AA0A0),
      offlineBadge: Color(0xFF3A2C0F),
      onOfflineBadge: Color(0xFFFFD08A),
      errorBubble: Color(0xFF3A1918),
      onErrorBubble: Color(0xFFFFB4AB),
      online: MamaColors.brandMint,
      offline: Color(0xFFE7C27D),
    ),
    brand: const MamaSurfaceColors(
      // Nearly black at the top, with only a whisper of green-tinted
      // charcoal at the bottom. This is the "Gemini glow", but much calmer.
      backgroundGradient: [
        Color(0xFF0E0F0F),
        Color(0xFF0E100F),
        Color(0xFF0E1512),
        Color(0xFF0F1A15),
      ],
      aurora: [Color(0xFF0E7C58), Color(0xFF146B63), MamaColors.slateGlowDark],
      ctaGradient: [Color(0xFF0D6449), Color(0xFF107A58)],
      onCta: Color(0xFFFFFFFF),
      glassFill: Color(0x14FFFFFF),
      glassBorder: Color(0x26FFFFFF),
    ),
  );

  static ThemeData _build({
    required ColorScheme scheme,
    required MamaChatColors chat,
    required MamaSurfaceColors brand,
    required Color scaffold,
  }) {
    final isDark = scheme.brightness == Brightness.dark;
    final overlay =
        (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(statusBarColor: Colors.transparent);
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    const buttonSize = Size(48, 52);

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      extensions: <ThemeExtension<dynamic>>[
        chat,
        brand,
        isDark ? MamaHeroColors.dark : MamaHeroColors.light,
      ],

      // The header is now a neutral surface in BOTH themes. In light mode it
      // is the same off-white as the page; in dark mode it is the same
      // charcoal. No bright green bar across the top.
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
        actionsIconTheme: IconThemeData(color: scheme.onSurface),
        systemOverlayStyle: overlay,
      ),

      // Square, borderless drawer - the Gemini look. The scrim (the dim layer
      // behind it) fades in/out with the drawer's built-in slide animation.
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrimColor: Colors.black.withValues(alpha: isDark ? 0.58 : 0.30),
        shape: const RoundedRectangleBorder(),
        width: 312,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),

      // Suggestion chips are neutral "cards" with a thin border, not green
      // blobs. This is the same treatment Gemini uses for its suggestion pills.
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.primaryContainer,
        disabledColor: scheme.surfaceContainerLow,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 13.5,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: buttonSize,
          shape: buttonShape,
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: buttonSize,
          shape: buttonShape,
          side: BorderSide(color: scheme.outline),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.7),
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.25),
        selectionHandleColor: scheme.primary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 15,
          height: 1.45,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: TextStyle(color: scheme.onSurface),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
      ),
    );
  }
}
