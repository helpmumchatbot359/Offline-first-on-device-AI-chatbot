import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mama_logo.dart';
import '../../../core/widgets/theme_toggle_button.dart';
import '../../auth/presentation/pages/auth_page.dart';

/// The first screen a new mum sees.
///
/// Unlike the rest of the app, onboarding is intentionally a single, rich
/// colour. A full-bleed emerald backdrop, an editorial photo and a large
/// bottom headline make the product feel warm and human before the person
/// has even created an account. Green stays the hero here; inside the app it
/// goes back to being an accent so long reading sessions remain comfortable.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool _precacheStarted = false;
  bool _imagesReady = false;

  /// The copy is deliberately short enough to fit over the photo on a small
  /// phone. Each line break is intentional: it gives the headline the same
  /// poster-like rhythm as the reference design.
  static const List<OnboardingItem> _slides = [
    OnboardingItem(
      imageAsset: 'assets/images/onboarding/helpmum_adviser.jpg',
      eyebrow: 'Here for you',
      iconData: Icons.volunteer_activism_rounded,
      title: 'Support for every\nstep of motherhood.',
      description: 'Friendly guidance for pregnancy, birth and newborn care.',
      imageAlignment: Alignment(0, -0.15),
    ),
    OnboardingItem(
      imageAsset: 'assets/images/onboarding/helpmum_care_team.jpg',
      eyebrow: 'A caring team',
      iconData: Icons.health_and_safety_rounded,
      title: 'Care and answers\nyou can trust.',
      description: 'HelpMum is here to support you and your little one.',
      imageAlignment: Alignment(0, -0.12),
    ),
    OnboardingItem(
      imageAsset: 'assets/images/onboarding/child_care.jpg',
      eyebrow: 'Care for your child',
      iconData: Icons.child_care_rounded,
      title: 'A healthier start\nfor every child.',
      description:
          'Get trusted guidance on your child’s health, growth and wellbeing.',
      imageAlignment: Alignment(0, -0.10),
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Start loading all photos while the first slide is visible. Slide
    // changes stay disabled until they are ready.
    if (_precacheStarted) return;
    _precacheStarted = true;
    unawaited(_precacheSlides());
  }

  Future<void> _precacheSlides() async {
    // Decode each photo at roughly the size it will be drawn instead of its
    // full 1600x2400 camera resolution. That is the difference between a
    // visible "empty green" pause and a photo that is already there.
    final cacheWidth = _decodeWidth(context);
    await Future.wait(
      _slides.map((slide) async {
        try {
          await precacheImage(
            ResizeImage(AssetImage(slide.imageAsset), width: cacheWidth),
            context,
          );
        } catch (_) {
          // Keep onboarding usable if a photo is missing; _HeroImage has a
          // fallback icon for that case.
        }
      }),
    );
    if (!mounted) return;
    setState(() => _imagesReady = true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openAuth({required bool isSignIn}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AuthPage(initialSignIn: isSignIn),
      ),
    );
  }

  void _continue() {
    unawaited(HapticFeedback.lightImpact());

    if (_currentIndex < _slides.length - 1) {
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      unawaited(
        _pageController.nextPage(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        ),
      );
      return;
    }

    // The last slide's call-to-action is the natural start of the account
    // flow, so it opens Sign Up rather than Sign In.
    _openAuth(isSignIn: false);
  }

  @override
  Widget build(BuildContext context) {
    // Read from the theme so the green cross-fades smoothly when the person
    // switches between light and dark instead of flashing.
    final palette = context.heroColors;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The page is dark green in both themes, so the status-bar and
      // navigation-bar icons are always light.
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarColor: palette.bottom,
        systemNavigationBarDividerColor: palette.bottom,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: palette.bottom,
        body: Stack(
          children: [
            Positioned.fill(child: _OnboardingBackdrop(palette: palette)),
            SafeArea(
              // Keep large accessibility text useful without letting the
              // poster headline overflow its photo on small screens.
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.35,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 20, 0),
                      child: _TopBar(onSignIn: () => _openAuth(isSignIn: true)),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        physics: _imagesReady
                            ? const PageScrollPhysics()
                            : const NeverScrollableScrollPhysics(),
                        itemCount: _slides.length,
                        onPageChanged: (index) {
                          unawaited(HapticFeedback.selectionClick());
                          setState(() => _currentIndex = index);
                        },
                        itemBuilder: (context, index) =>
                            _SlideView(slide: _slides[index], palette: palette),
                      ),
                    ),
                    _BottomBar(
                      count: _slides.length,
                      currentIndex: _currentIndex,
                      isLast: _currentIndex == _slides.length - 1,
                      enabled: _imagesReady,
                      onContinue: _continue,
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

/// Logo on the left, theme switch and Sign In on the right.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // A thin white frame makes HelpMum's teal square read as a crisp app
        // icon instead of a coloured block floating on the green.
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: const MamaLogo(size: 34),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'MamaBot',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: Colors.white,
            ),
          ),
        ),
        ThemeToggleButton(
          foregroundColor: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: 0.12),
          compact: true,
        ),
        const SizedBox(width: 8),
        _SignInButton(onPressed: onSignIn),
      ],
    );
  }
}

class _SignInButton extends StatelessWidget {
  const _SignInButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        // A deep-green tint (instead of white) keeps the small label readable
        // against the brighter top of the background.
        backgroundColor: const Color(0xFF033D2B).withValues(alpha: 0.30),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 15),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: StadiumBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
      child: const Text('Sign in'),
    );
  }
}

/// One full-page slide: the photo behind, the copy sitting on its lower fade.
class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.palette});

  final OnboardingItem slide;
  final MamaHeroColors palette;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _HeroImage(slide: slide, palette: palette),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              _SlideCopy(slide: slide),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroImage extends StatelessWidget {
  const _HeroImage({required this.slide, required this.palette});

  final OnboardingItem slide;
  final MamaHeroColors palette;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          slide.imageAsset,
          fit: BoxFit.cover,
          alignment: slide.imageAlignment,
          // Match the size used by precacheImage so the work is reused and
          // the photo appears as soon as its first frame is decoded.
          cacheWidth: _decodeWidth(context),
          gaplessPlayback: true,
          semanticLabel: slide.title.replaceAll('\n', ' '),
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (context, error, stackTrace) => ColoredBox(
            color: palette.mid,
            child: Center(
              child: Icon(
                slide.iconData,
                size: 88,
                color: Colors.white.withValues(alpha: 0.38),
              ),
            ),
          ),
        ),

        // The photo is not placed in a box: its top dissolves into the
        // header and its bottom into the copy. That soft blend is the trick
        // that makes the reference design feel like one continuous surface.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  palette.top.withValues(alpha: 0.92),
                  palette.top.withValues(alpha: 0.18),
                  Colors.transparent,
                  Colors.transparent,
                  palette.bottom.withValues(alpha: 0.55),
                  palette.bottom.withValues(alpha: 0.92),
                  palette.bottom,
                ],
                stops: const [0.0, 0.07, 0.18, 0.40, 0.58, 0.80, 1.0],
              ),
            ),
          ),
        ),

        // A faint vignette adds depth and keeps the eye on the subject.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.18),
                radius: 1.05,
                colors: [
                  Colors.transparent,
                  palette.bottom.withValues(alpha: 0.26),
                ],
                stops: const [0.62, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SlideCopy extends StatelessWidget {
  const _SlideCopy({required this.slide});

  final OnboardingItem slide;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = (width * 0.095).clamp(30.0, 38.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
          ),
          // Just the label now: the little icon beside it was decorative
          // noise and added nothing to the meaning.
          child: Text(
            slide.eyebrow.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: Color(0xFFE6FFF3),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          slide.title,
          style: TextStyle(
            fontSize: titleSize,
            height: 1.04,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 18,
                offset: const Offset(0, 3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 332),
          child: Text(
            slide.description,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.45,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.80),
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Page progress on the left, one clear action on the right.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.count,
    required this.currentIndex,
    required this.isLast,
    required this.enabled,
    required this.onContinue,
  });

  final int count;
  final int currentIndex;
  final bool isLast;
  final bool enabled;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Row(
        children: [
          _PageIndicator(count: count, currentIndex: currentIndex),
          const Spacer(),
          AnimatedSize(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: _CtaButton(
              key: ValueKey(isLast),
              label: enabled
                  ? (isLast ? 'Get started' : 'Next')
                  : 'Loading photos…',
              onPressed: enabled ? onContinue : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.count, required this.currentIndex});

  final int count;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Row(
      children: List.generate(count, (index) {
        final active = index == currentIndex;
        return AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.only(right: 7),
          width: active ? 28 : 7,
          height: 5,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.36),
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }
}

/// Soft mint pill with a deep-green label and arrow.
class _CtaButton extends StatelessWidget {
  const _CtaButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  static const _ink = Color(0xFF033D2B);
  static const _radius = BorderRadius.all(Radius.circular(999));

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: _radius,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFD9FFEC), Color(0xFF8DF0C5)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF01150E).withValues(alpha: 0.34),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: _radius,
            onTap: onPressed,
            splashColor: Colors.white.withValues(alpha: 0.30),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: SizedBox(
                height: 52,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _ink.withValues(alpha: 0.10),
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingBackdrop extends StatelessWidget {
  const _OnboardingBackdrop({required this.palette});

  final MamaHeroColors palette;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // Hold the top colour through the header so the photo's own
              // top fade lands on exactly the same green, with no seam.
              colors: [palette.top, palette.top, palette.mid, palette.bottom],
              stops: const [0.0, 0.18, 0.55, 1.0],
            ),
          ),
        ),
        Positioned(
          top: -160,
          right: -120,
          child: _Glow(size: 400, color: palette.glow, opacity: 0.22),
        ),
        Positioned(
          bottom: -220,
          left: -180,
          child: _Glow(size: 460, color: palette.glow2, opacity: 0.18),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color, required this.opacity});

  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// One onboarding slide: its photo, copy and the icon used in the eyebrow.
class OnboardingItem {
  const OnboardingItem({
    required this.imageAsset,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.iconData,
    required this.imageAlignment,
  });

  final String imageAsset;
  final String eyebrow;
  final String title;
  final String description;
  final IconData iconData;

  /// Where the photo should be anchored when `BoxFit.cover` crops it.
  final Alignment imageAlignment;
}

/// The width a photo should be decoded at. The source files are 1600 px wide
/// (and 2400 px tall); decoding them at full size on a phone is slow and uses
/// a lot of memory. Screen width is all we ever actually draw.
int _decodeWidth(BuildContext context) {
  final media = MediaQuery.maybeOf(context);
  if (media == null) return 960;
  // 0.85x the physical width is still sharp for a full-bleed photo but cuts
  // the decoded pixel count noticeably, so the first frame arrives sooner.
  final wanted = (media.size.width * media.devicePixelRatio * 0.85).round();
  if (wanted < 480) return 480;
  if (wanted > 1280) return 1280;
  return wanted;
}
