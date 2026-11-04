import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mama_logo.dart';
import '../../../core/widgets/theme_toggle_button.dart';
import '../../auth/presentation/pages/auth_page.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  final List<OnboardingItem> _slides = [
    const OnboardingItem(
      title: 'Expert Guidance for Mums',
      description: 'Get instant, reliable answers about pregnancy, nutrition, and newborn care right from your pocket.',
      iconData: Icons.favorite_rounded,
    ),
    const OnboardingItem(
      title: 'Works Completely Offline',
      description: 'No internet? No problem. MamaBot includes an on-device assistant so you can get help anywhere, anytime.',
      iconData: Icons.cloud_off_rounded,
    ),
    const OnboardingItem(
      title: 'Track Vaccines & Safety',
      description: 'Stay on top of critical immunizations and learn to spot early pregnancy warning signs instantly.',
      iconData: Icons.verified_rounded,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _navigateToAuth(BuildContext context, {required bool isSignIn}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AuthPage(initialSignIn: isSignIn),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = context.brandColors;
    final isDark = theme.brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // No AppBar exists here, so the status-bar icons need to be told which
      // colour to use. White icons in dark mode, dark icons in light mode.
      value: (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        body: Stack(
          children: [
            // 1) The base colour wash. It is a normal gradient, so it costs
            //    almost nothing to draw.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: brand.backgroundGradient,
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),

            // 2) Slow-moving light blobs on top of the wash. This is the
            //    "Gemini-like" glow, using our own green family.
            Positioned.fill(
              child: _AuroraBackground(colors: brand.aurora, isDark: isDark),
            ),

            // 3) Everything the person can actually read and tap.
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Column(
                  children: [
                    _TopBar(
                      onSignIn: () => _navigateToAuth(context, isSignIn: true),
                    ),
                    const SizedBox(height: 8),

                    // Swipeable slides
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _slides.length,
                        onPageChanged: (index) {
                          setState(() => _currentIndex = index);
                        },
                        itemBuilder: (context, index) {
                          final slide = _slides[index];
                          return _SlideView(slide: slide);
                        },
                      ),
                    ),

                    // Page indicator dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _slides.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentIndex == index ? 28 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            gradient: _currentIndex == index
                                ? LinearGradient(
                                    colors: [
                                      scheme.primary,
                                      Color.lerp(
                                        scheme.primary,
                                        brand.ctaGradient.last,
                                        0.55,
                                      )!,
                                    ],
                                  )
                                : null,
                            color: _currentIndex == index
                                ? null
                                : scheme.outlineVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Primary action (Next or Get Started)
                    SizedBox(
                      width: double.infinity,
                      child: _GradientButton(
                        label: _currentIndex == _slides.length - 1
                            ? 'Get Started'
                            : 'Next',
                        onPressed: () {
                          if (_currentIndex < _slides.length - 1) {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOutCubic,
                            );
                          } else {
                            // Final slide: default "Get Started" opens Sign Up.
                            _navigateToAuth(context, isSignIn: false);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Secondary action
                    if (_currentIndex < _slides.length - 1)
                      TextButton(
                        onPressed: () {
                          _pageController.animateToPage(
                            _slides.length - 1,
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                          );
                        },
                        child: Text(
                          'Skip',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    else
                      TextButton(
                        onPressed: () =>
                            _navigateToAuth(context, isSignIn: true),
                        child: Text(
                          'Already have an account? Sign In',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo on the left, theme switch and "Sign In" on the right.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        // The HelpMum logo is already a square tile with its own teal
        // background, so it never needed a circle around it. Rounded corners
        // let the whole picture show without clipping anything.
        const ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          child: MamaLogo(size: 38),
        ),
        const SizedBox(width: 10),
        Text(
          'MamaBot',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: scheme.onSurface,
          ),
        ),
        const Spacer(),
        const ThemeToggleButton(),
        TextButton(
          onPressed: onSignIn,
          child: Text(
            'Sign In',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}

/// One onboarding slide: a floating glass icon, a title and a description.
class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final OnboardingItem slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = context.brandColors;
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 136,
              height: 136,
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primary.withValues(alpha: isDark ? 0.85 : 0.7),
                    brand.glassBorder,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(
                      alpha: isDark ? 0.28 : 0.18,
                    ),
                    blurRadius: 48,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: brand.glassFill,
                ),
                child: Icon(slide.iconData, size: 60, color: scheme.primary),
              ),
            ),
            const SizedBox(height: 38),
            Text(
              slide.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 27,
                height: 1.18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                slide.description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pill-shaped button painted with the theme's green gradient.
class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final brand = context.brandColors;
    final radius = BorderRadius.circular(18);

    return Semantics(
      button: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: brand.ctaGradient,
          ),
          boxShadow: [
            BoxShadow(
              color: brand.ctaGradient.last.withValues(alpha: 0.35),
              blurRadius: 22,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: onPressed,
            child: SizedBox(
              height: 54,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: brand.onCta,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The animated part of the background.
///
/// A [CustomPainter] is used instead of many `Container`s because it draws
/// directly on one canvas. The [RepaintBoundary] means only this layer is
/// repainted while the blobs move, not the text and buttons above it.
class _AuroraBackground extends StatefulWidget {
  const _AuroraBackground({required this.colors, required this.isDark});

  final List<Color> colors;
  final bool isDark;

  @override
  State<_AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<_AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 32),
  );

  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // If the phone's accessibility setting asks for less motion, freeze the
    // glow in a pleasant position instead of animating it forever.
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce == _reducedMotion) return;
    _reducedMotion = reduce;
    if (reduce) {
      _controller
        ..stop()
        ..value = 0.35;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _AuroraPainter(
            animation: _controller,
            colors: widget.colors,
            isDark: widget.isDark,
          ),
          isComplex: true,
          willChange: true,
        ),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.animation,
    required this.colors,
    required this.isDark,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final List<Color> colors;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || colors.isEmpty) return;

    final t = animation.value * math.pi * 2;
    final w = size.width;
    final h = size.height;
    final strength = isDark ? 0.46 : 0.34;

    // The light is deliberately anchored to the bottom of the screen, like the
    // blue pool in Gemini. The top half stays almost pure black (dark mode) or
    // near-white (light mode), so the green reads as a glow, not a wash.
    final blobs = <_GlowBlob>[
      _GlowBlob(
        center: Offset(
          w * (0.50 + 0.08 * math.sin(t)),
          h * (1.02 + 0.01 * math.cos(t)),
        ),
        radius: w * 1.18,
        color: colors[0],
      ),
      _GlowBlob(
        center: Offset(
          w * (0.10 + 0.08 * math.cos(t * 0.7)),
          h * (0.95 + 0.02 * math.sin(t * 0.8)),
        ),
        radius: w * 0.86,
        color: colors[1 % colors.length],
      ),
      if (colors.length > 2)
        _GlowBlob(
          center: Offset(
            w * (0.92 + 0.06 * math.sin(t * 0.5 + 1.2)),
            h * (0.98 + 0.02 * math.cos(t * 0.6)),
          ),
          radius: w * 0.78,
          color: colors[2],
        ),
    ];

    for (final blob in blobs) {
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          blob.center,
          blob.radius,
          [
            blob.color.withValues(alpha: strength),
            blob.color.withValues(alpha: 0),
          ],
          const [0.0, 1.0],
        );
      canvas.drawCircle(blob.center, blob.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate.isDark != isDark;
}

class _GlowBlob {
  const _GlowBlob({
    required this.center,
    required this.radius,
    required this.color,
  });

  final Offset center;
  final double radius;
  final Color color;
}

class OnboardingItem {
  const OnboardingItem({
    required this.title,
    required this.description,
    required this.iconData,
  });

  final String title;
  final String description;
  final IconData iconData;
}
