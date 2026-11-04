import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The calm background used behind the chat, auth and splash screens.
///
/// It is two very cheap layers:
///   1. A gentle top-to-bottom gradient (the "wash").
///   2. One almost-invisible radial glow near the bottom (the "light pool").
///
/// Both layers come from [MamaSurfaceColors], so light mode and dark mode
/// switch together and we never hard-code a colour in a screen.
class MamaBackground extends StatelessWidget {
  const MamaBackground({super.key, required this.child, this.showGlow = true});

  final Widget child;

  /// Turn the soft bottom glow off on screens where it would be distracting.
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    final brand = context.brandColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // A gradient needs at least two colours. If a theme ever supplies one,
    // duplicate it instead of crashing.
    final source = brand.backgroundGradient;
    final colors = source.length >= 2 ? source : [source.first, source.first];
    final stops = List<double>.generate(
      colors.length,
      (i) => i / (colors.length - 1),
    );

    // The last aurora colour is a cool slate. Using it for the glow (instead
    // of green) adds depth without turning the whole screen green.
    final glow = brand.aurora.isEmpty ? brand.glassBorder : brand.aurora.last;

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
              stops: stops,
            ),
          ),
        ),
        if (showGlow)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, 1.05),
                    radius: 1.15,
                    colors: [
                      glow.withValues(alpha: isDark ? 0.14 : 0.12),
                      glow.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
        Positioned.fill(child: child),
      ],
    );
  }
}
