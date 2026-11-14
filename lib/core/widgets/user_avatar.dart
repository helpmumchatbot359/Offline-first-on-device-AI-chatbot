import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.initial, this.radius = 18});

  final String initial;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF4A3026)
        : const Color(0xFFF2D8C8);
    final foreground = isDark
        ? const Color(0xFFF5CBB4)
        : const Color(0xFF7A3E24);

    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      foregroundColor: foreground,
      child: Text(
        initial.isEmpty ? 'M' : initial,
        style: TextStyle(
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color: foreground,
        ),
      ),
    );
  }
}
