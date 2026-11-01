import 'package:flutter/material.dart';

/// The HelpMum logo. Used on the splash screen, onboarding and empty chat.
///
/// The picture lives in `assets/HelpMumLogo.png` and must be listed under
/// `flutter: assets:` in pubspec.yaml.
class MamaLogo extends StatelessWidget {
  const MamaLogo({super.key, this.size = 48});

  /// Width and height of the logo in logical pixels.
  final double size;

  static const String assetPath = 'assets/HelpMumLogo.png';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'HelpMum logo',
      image: true,
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        // If the picture is ever missing the app shows a heart instead of crashing.
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.favorite_rounded,
          size: size,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}