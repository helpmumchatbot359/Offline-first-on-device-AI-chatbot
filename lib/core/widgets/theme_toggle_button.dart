import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme/theme_bloc/theme_bloc.dart';
import '../theme/theme_bloc/theme_event.dart';

/// Sun/moon button. Drop it in any AppBar's `actions`.
///
/// [foregroundColor] and [backgroundColor] let screens with a coloured,
/// full-bleed background (like onboarding) use a light icon on a translucent
/// circle without hard-coding the button's colours here.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({
    super.key,
    this.foregroundColor,
    this.backgroundColor,
    this.compact = false,
  });

  final Color? foregroundColor;
  final Color? backgroundColor;

  /// Shrinks the button from the default 48x48 tap target to 40x40. The
  /// onboarding header is tight, so it uses this variant.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = context.select<ThemeBloc, bool>((b) => b.state.isDark);
    return IconButton(
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      onPressed: () => context.read<ThemeBloc>().add(const ThemeToggled()),
      style: IconButton.styleFrom(
        foregroundColor: foregroundColor,
        backgroundColor: backgroundColor,
        minimumSize: compact ? const Size(40, 40) : null,
        padding: compact ? EdgeInsets.zero : null,
        tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
      ),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => RotationTransition(
          turns: Tween<double>(begin: 0.75, end: 1).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          key: ValueKey<bool>(isDark),
        ),
      ),
    );
  }
}
