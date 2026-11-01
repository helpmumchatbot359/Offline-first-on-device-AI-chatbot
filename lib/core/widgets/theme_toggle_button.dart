import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../theme/theme_bloc/theme_bloc.dart';
import '../theme/theme_bloc/theme_event.dart';

/// Sun/moon button. Drop it in any AppBar's `actions`.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.select<ThemeBloc, bool>((b) => b.state.isDark);
    return IconButton(
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      onPressed: () => context.read<ThemeBloc>().add(const ThemeToggled()),
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
