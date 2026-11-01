import 'package:flutter/material.dart';
import '../../../core/widgets/mama_logo.dart';
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
      description:
          'Get instant, reliable answers about pregnancy, nutrition, and newborn care right from your pocket.',
      iconData: Icons.favorite_rounded,
    ),
    const OnboardingItem(
      title: 'Works Completely Offline',
      description:
          'No internet? No problem. MamaBot includes an on-device assistant so you can get help anywhere, anytime.',
      iconData: Icons.cloud_off_rounded,
    ),
    const OnboardingItem(
      title: 'Track Vaccines & Safety',
      description:
          'Stay on top of critical immunizations and learn to spot early pregnancy warning signs instantly.',
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Top Bar: Logo, Name, and Quick "Sign In" Button for returning users
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const MamaLogo(size: 36),
                      const SizedBox(width: 10),
                      Text(
                        'MamaBot',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => _navigateToAuth(context, isSignIn: true),
                    child: Text(
                      'Sign In',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Swipeable Slides
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _slides.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    final slide = _slides[index];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            slide.iconData,
                            size: 60,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          slide.description,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.4,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // Page Indicator Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentIndex == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentIndex == index
                          ? colorScheme.primary
                          : colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Primary Action (Next or Get Started)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (_currentIndex < _slides.length - 1) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    } else {
                      // Final slide: default "Get Started" opens Sign Up form
                      _navigateToAuth(context, isSignIn: false);
                    }
                  },
                  child: Text(
                    _currentIndex == _slides.length - 1
                        ? 'Get Started'
                        : 'Next',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Secondary Action (Skip to last slide OR Quick Sign In link)
              if (_currentIndex < _slides.length - 1)
                TextButton(
                  onPressed: () {
                    _pageController.jumpToPage(_slides.length - 1);
                  },
                  child: Text(
                    'Skip',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                )
              else
                TextButton(
                  onPressed: () => _navigateToAuth(context, isSignIn: true),
                  child: Text(
                    'Already have an account? Sign In',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
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