import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/mama_logo.dart';
import '../../../../core/widgets/theme_toggle_button.dart';
import '../bloc/auth_bloc.dart';
import '../events/auth_event.dart';
import '../states/auth_state.dart';

/// Sign in / create account — the second half of the welcome story.
///
/// The onboarding screen ends on a green, photographic note. Instead of
/// dropping the person onto a plain white form, this page keeps the same
/// emerald world and slides a soft, editorial card on top of it. The card is
/// where all the "work" lives, so the form itself stays calm and readable:
/// generous spacing, one clear primary action and one gentle hint of motion.
///
/// Everything below is intentionally private to this file, just like the
/// onboarding page, so the whole feature can be read from top to bottom.
class AuthPage extends StatefulWidget {
  const AuthPage({super.key, this.initialSignIn = true});

  final bool initialSignIn;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with TickerProviderStateMixin {
  // ── Form state ──────────────────────────────────────────────────────────
  // A new form key is created whenever the tabs switch. That clears any
  // validation messages instantly while keeping the text the person typed.
  GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _countryController = TextEditingController();

  final _passwordFocus = FocusNode();

  late bool _isSignIn;
  bool _obscurePassword = true;
  String? _selectedGender;

  /// A single note shown just above the fields. Errors and the "account
  /// created" confirmation both use this calm, inline pattern instead of a
  /// snackbar, so nothing covers the keyboard.
  String? _feedback;
  bool _feedbackIsError = false;

  // ── Motion ──────────────────────────────────────────────────────────────
  late final AnimationController _entrance;
  late final AnimationController _aurora;
  bool _motionStarted = false;

  late final Animation<double> _topReveal;
  late final Animation<Offset> _topSlide;
  late final Animation<double> _heroReveal;
  late final Animation<Offset> _heroSlide;
  late final Animation<double> _cardReveal;
  late final Animation<Offset> _cardSlide;

  /// A slightly friendlier email check than the original one: it accepts
  /// addresses like `ada+mother@example.co.uk` that people really use.
  static final RegExp _emailRegExp = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  @override
  void initState() {
    super.initState();
    _isSignIn = widget.initialSignIn;

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _aurora = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
    );

    // Each section owns a small slice of the same controller. The result is
    // a gentle top-to-bottom "settle" rather than everything fading at once.
    _topReveal = _entrance.drive(
      CurveTween(curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic)),
    );
    _topSlide = _topReveal.drive(
      Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero),
    );
    _heroReveal = _entrance.drive(
      CurveTween(curve: const Interval(0.08, 0.62, curve: Curves.easeOutCubic)),
    );
    _heroSlide = _heroReveal.drive(
      Tween<Offset>(begin: const Offset(0, 0.10), end: Offset.zero),
    );
    _cardReveal = _entrance.drive(
      CurveTween(curve: const Interval(0.20, 0.92, curve: Curves.easeOutCubic)),
    );
    _cardSlide = _cardReveal.drive(
      Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionStarted) return;
    _motionStarted = true;

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      // Show the finished layout immediately for people who turn motion off.
      _entrance.value = 1;
      return;
    }
    _entrance.forward();
    _aurora.repeat();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _aurora.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _countryController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // ── Actions ─────────────────────────────────────────────────────────────
  void _setSignIn(bool signIn) {
    if (_isSignIn == signIn) return;
    unawaited(HapticFeedback.selectionClick());

    setState(() {
      _isSignIn = signIn;
      // A fresh FormState drops the old error text without clearing text.
      _formKey = GlobalKey<FormState>();
      _feedback = null;
    });
  }

  void _submit(AuthState state) {
    if (state.busy) return;

    FocusManager.instance.primaryFocus?.unfocus();
    if (_feedback != null) {
      setState(() => _feedback = null);
    }

    if (!_formKey.currentState!.validate()) {
      // A tiny physical cue that something needs attention.
      unawaited(HapticFeedback.mediumImpact());
      return;
    }

    final authBloc = context.read<AuthBloc>();
    if (_isSignIn) {
      authBloc.add(
        SignInSubmitted(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        ),
      );
    } else {
      authBloc.add(
        SignUpSubmitted(
          username: _usernameController.text.trim(),
          gender: _selectedGender ?? '',
          email: _emailController.text.trim(),
          country: _countryController.text.trim(),
          password: _passwordController.text.trim(),
        ),
      );
    }
  }

  /// Turns bloc state into the two things this screen cares about:
  /// a one-off "account created" moment and plain error messages.
  void _onAuthState(AuthState state) {
    if (!mounted) return;

    if (state.justSignedUp) {
      setState(() {
        _isSignIn = true;
        _formKey = GlobalKey<FormState>();
        _passwordController.clear();
        _obscurePassword = true;
        _selectedGender = null;
        _feedback = 'Account created. Sign in to continue.';
        _feedbackIsError = false;
      });

      // The email is still there, so put the cursor where the person needs
      // it next. Post-frame keeps the keyboard from opening during the tab
      // animation.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _passwordFocus.requestFocus();
      });
      return;
    }

    if (state.error != null && state.error != _feedback) {
      setState(() {
        _feedback = state.error;
        _feedbackIsError = true;
      });
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hero = MamaHeroColors(isDark: isDark);
    final formColors = _AuthFormColors(isDark: isDark);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The page is deep green in both themes, so status and navigation bar
      // icons are always light.
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarColor: hero.bottom,
        systemNavigationBarDividerColor: hero.bottom,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: hero.bottom,
        body: Stack(
          children: [
            // The animated layer is isolated so the form never repaints when
            // the glows drift.
            Positioned.fill(
              child: RepaintBoundary(
                child: _AuthBackdrop(palette: hero, animation: _aurora),
              ),
            ),
            SafeArea(
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 14, 0),
                      child: _Reveal(
                        opacity: _topReveal,
                        slide: _topSlide,
                        child: _AuthTopBar(
                          onBack: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _Reveal(
                                  opacity: _heroReveal,
                                  slide: _heroSlide,
                                  child: _Hero(isSignIn: _isSignIn),
                                ),
                                const SizedBox(height: 22),
                                _Reveal(
                                  opacity: _cardReveal,
                                  slide: _cardSlide,
                                  child: BlocConsumer<AuthBloc, AuthState>(
                                    listenWhen: (previous, current) =>
                                        previous.error != current.error ||
                                        previous.justSignedUp !=
                                            current.justSignedUp,
                                    listener: (context, state) =>
                                        _onAuthState(state),
                                    builder: (context, state) =>
                                        _buildCard(state, formColors),
                                  ),
                                ),
                              ],
                            ),
                          ),
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

  Widget _buildCard(AuthState state, _AuthFormColors colors) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return _AuthCardShell(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModeTabs(isSignIn: _isSignIn, onChanged: _setSignIn, colors: colors),

          // Feedback note: grows the card only when there is something to
          // say. Reduced-motion users get the finished layout instantly.
          _buildFeedback(colors, reduceMotion),

          const SizedBox(height: 18),
          Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Sign-up-only fields. They fold away smoothly when the
                  // person switches back to sign in.
                  AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      alignment: Alignment.topCenter,
                      children: [...previousChildren, ?currentChild],
                    ),
                    transitionBuilder: (child, animation) => SizeTransition(
                      sizeFactor: animation,
                      alignment: Alignment.topCenter,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: _isSignIn
                        ? const SizedBox(
                            key: ValueKey('no-sign-up-fields'),
                            width: double.infinity,
                          )
                        : _buildSignUpFields(colors),
                  ),

                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.none,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.email],
                    style: _inputStyle(colors),
                    cursorColor: colors.accent,
                    decoration: _fieldDecoration(
                      colors: colors,
                      label: 'Email address',
                      hint: 'you@example.com',
                      icon: Icons.alternate_email_rounded,
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (email.isEmpty) {
                        return 'Email address is required';
                      }
                      if (!_emailRegExp.hasMatch(email)) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    obscureText: _obscurePassword,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: [
                      _isSignIn
                          ? AutofillHints.password
                          : AutofillHints.newPassword,
                    ],
                    style: _inputStyle(colors),
                    cursorColor: colors.accent,
                    onFieldSubmitted: (_) => _submit(state),
                    decoration: _fieldDecoration(
                      colors: colors,
                      label: 'Password',
                      hint: _isSignIn
                          ? 'Your password'
                          : 'At least 6 characters',
                      icon: Icons.lock_outline_rounded,
                      suffix: IconButton(
                        tooltip: _obscurePassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        style: IconButton.styleFrom(
                          foregroundColor: colors.muted,
                          minimumSize: const Size(44, 44),
                        ),
                        icon: AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          child: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            key: ValueKey(_obscurePassword),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    validator: (value) {
                      final password = value ?? '';
                      if (password.trim().isEmpty) {
                        return 'Password is required';
                      }
                      if (password.trim().length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 22),

                  _GradientButton(
                    label: _isSignIn ? 'Sign in' : 'Create account',
                    busyLabel: _isSignIn ? 'Signing in' : 'Creating account',
                    busy: state.busy,
                    isDark: colors.isDark,
                    onPressed: () => _submit(state),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _CardFooter(colors: colors),
        ],
      ),
    );
  }

  Widget _buildFeedback(_AuthFormColors colors, bool reduceMotion) {
    final note = _feedback == null
        ? const SizedBox(width: double.infinity)
        : Padding(
            padding: const EdgeInsets.only(top: 14),
            child: _Notice(
              message: _feedback!,
              isError: _feedbackIsError,
              colors: colors,
            ),
          );

    if (reduceMotion) return note;

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: note,
    );
  }

  Widget _buildSignUpFields(_AuthFormColors colors) {
    return Column(
      key: const ValueKey('sign-up-fields'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _usernameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newUsername],
          style: _inputStyle(colors),
          cursorColor: colors.accent,
          decoration: _fieldDecoration(
            colors: colors,
            label: 'Username',
            hint: 'What should we call you?',
            icon: Icons.person_outline_rounded,
          ),
          // If the sign-in form is still fading in, its hidden fields must
          // never block the submit button. That is why every sign-up
          // validator starts with this guard.
          validator: (value) {
            if (_isSignIn) return null;
            if (value == null || value.trim().isEmpty) {
              return 'Username is required';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),

        DropdownButtonFormField<String>(
          initialValue: _selectedGender,
          isExpanded: true,
          style: _inputStyle(colors),
          decoration: _fieldDecoration(
            colors: colors,
            label: 'Gender',
            hint: 'Select',
            icon: Icons.wc_rounded,
          ),
          hint: Text(
            'Select',
            style: _inputStyle(colors)
                .copyWith(color: colors.muted, fontWeight: FontWeight.w400),
          ),
          dropdownColor: colors.menu,
          borderRadius: BorderRadius.circular(16),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: colors.muted),
          items: const [
            DropdownMenuItem(value: 'Female', child: Text('Female')),
            DropdownMenuItem(value: 'Male', child: Text('Male')),
          ],
          onChanged: (value) => setState(() => _selectedGender = value),
          validator: (value) {
            if (_isSignIn) return null;
            if (value == null || value.isEmpty) {
              return 'Please select your gender';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),

        TextFormField(
          controller: _countryController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.countryName],
          style: _inputStyle(colors),
          cursorColor: colors.accent,
          decoration: _fieldDecoration(
            colors: colors,
            label: 'Country',
            hint: 'e.g. Nigeria',
            icon: Icons.public_rounded,
          ),
          validator: (value) {
            if (_isSignIn) return null;
            if (value == null || value.trim().isEmpty) {
              return 'Country is required';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  // ── Small styling helpers ───────────────────────────────────────────────
  TextStyle _inputStyle(_AuthFormColors colors) {
    final base = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
    return base.copyWith(
      color: colors.ink,
      fontSize: 15,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.05,
    );
  }

  InputDecoration _fieldDecoration({
    required _AuthFormColors colors,
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffix,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final baseText = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
    final radius = BorderRadius.circular(16);

    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      // A widget label lets the asterisk stay red while the text keeps the
      // decorator's floating-label animation.
      label: Text.rich(
        TextSpan(
          text: label,
          style: TextStyle(color: colors.muted),
          children: [
            TextSpan(
              text: ' *',
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      hintText: hint,
      hintStyle: baseText.copyWith(
        color: colors.muted.withValues(alpha: 0.70),
        fontSize: 14.5,
      ),
      filled: true,
      fillColor: colors.fieldFill,
      prefixIcon: Icon(icon, size: 20, color: colors.muted),
      prefixIconConstraints: const BoxConstraints(minWidth: 46, minHeight: 24),
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: border(colors.fieldBorder),
      enabledBorder: border(colors.fieldBorder),
      focusedBorder: border(scheme.primary, 1.6),
      errorBorder: border(scheme.error.withValues(alpha: 0.65)),
      focusedErrorBorder: border(scheme.error, 1.6),
      errorStyle: baseText.copyWith(
        color: scheme.error,
        fontSize: 12,
        height: 1.35,
      ),
      errorMaxLines: 2,
      labelStyle: WidgetStateTextStyle.resolveWith((states) {
        return baseText.copyWith(
          color: states.contains(WidgetState.error)
              ? scheme.error
              : colors.muted,
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
        );
      }),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
        final color = states.contains(WidgetState.error)
            ? scheme.error
            : states.contains(WidgetState.focused)
            ? scheme.primary
            : colors.muted;
        return baseText.copyWith(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        );
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Layout pieces
// ═══════════════════════════════════════════════════════════════════════════

/// Fade + slide, driven by one section of the entrance timeline.
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.opacity,
    required this.slide,
    required this.child,
  });

  final Animation<double> opacity;
  final Animation<Offset> slide;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: opacity,
      child: SlideTransition(position: slide, child: child),
    );
  }
}

/// Back button on the left, the brand in the middle, theme switch on the
/// right. The same recipe as the onboarding header, so moving between the
/// two screens feels like walking through one product.
class _AuthTopBar extends StatelessWidget {
  const _AuthTopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
          style: IconButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.white.withValues(alpha: 0.10),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
            minimumSize: const Size(40, 40),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: const MamaLogo(size: 28),
          ),
        ),
        const SizedBox(width: 9),
        const Expanded(
          child: Text(
            'MamaBot',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: Colors.white,
            ),
          ),
        ),
        ThemeToggleButton(
          foregroundColor: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: 0.10),
          compact: true,
        ),
      ],
    );
  }
}

/// The headline block above the card. It changes with the tab, but the
/// rhythm stays identical so the page never jumps around.
class _Hero extends StatelessWidget {
  const _Hero({required this.isSignIn});

  final bool isSignIn;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 320);
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = (width * 0.095).clamp(30.0, 38.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AnimatedSwitcher(
          duration: duration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: animation.drive(
                Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero),
              ),
              child: child,
            ),
          ),
          child: SizedBox(
            key: ValueKey(isSignIn),
            width: double.infinity,
            child: Text(
              isSignIn ? 'Welcome back,\nMama.' : 'Let\'s get you\nstarted.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: titleSize,
                height: 1.04,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.1,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: SizedBox(
              key: ValueKey('subtitle-$isSignIn'),
              width: double.infinity,
              child: Text(
                isSignIn
                    ? 'Sign in to pick up your care journey right where you left off.'
                    : 'Create your account for guidance shaped around you and your baby.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.5,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withValues(alpha: 0.88),
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The white (or charcoal) sheet that holds the form. A one-pixel gradient
/// edge catches the light, which is what makes it read as "glass" without
/// the cost of a live backdrop blur.
class _AuthCardShell extends StatelessWidget {
  const _AuthCardShell({required this.colors, required this.child});

  final _AuthFormColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const outerRadius = BorderRadius.all(Radius.circular(28));
    const innerRadius = BorderRadius.all(Radius.circular(27));

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: outerRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.cardEdge,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF01150E)
                .withValues(alpha: colors.isDark ? 0.50 : 0.30),
            blurRadius: 40,
            spreadRadius: -6,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: Padding(
        // The padding is the border: the gradient behind shows through.
        padding: const EdgeInsets.all(1),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: innerRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors.card,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Two tabs with a pill that slides across. Better than a text link at the
/// bottom because the choice is visible before any typing happens.
class _ModeTabs extends StatelessWidget {
  const _ModeTabs({
    required this.isSignIn,
    required this.onChanged,
    required this.colors,
  });

  final bool isSignIn;
  final ValueChanged<bool> onChanged;
  final _AuthFormColors colors;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selectedGradient = colors.isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4ADE9B), Color(0xFF2FCB8C)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F8A62), Color(0xFF0B7A55)],
          );
    final selectedInk = colors.isDark ? const Color(0xFF04251C) : Colors.white;

    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.tabTrack,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.tabTrackBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / 2;
          return Stack(
            fit: StackFit.expand,
            children: [
              AnimatedPositioned(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: isSignIn ? 0 : tabWidth,
                top: 0,
                bottom: 0,
                width: tabWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    gradient: selectedGradient,
                    boxShadow: [
                      BoxShadow(
                        color: selectedGradient.colors.last.withValues(
                          alpha: colors.isDark ? 0.22 : 0.26,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _Tab(
                      label: 'Sign in',
                      selected: isSignIn,
                      selectedInk: selectedInk,
                      unselectedInk: colors.muted,
                      onTap: () => onChanged(true),
                    ),
                  ),
                  Expanded(
                    child: _Tab(
                      label: 'Sign up',
                      selected: !isSignIn,
                      selectedInk: selectedInk,
                      unselectedInk: colors.muted,
                      onTap: () => onChanged(false),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.selectedInk,
    required this.unselectedInk,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedInk;
  final Color unselectedInk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    // Start from the ambient style so the tab picks up the app font (and
    // any future font change) instead of falling back to the platform one.
    final base = DefaultTextStyle.of(context).style;
    return Semantics(
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              style: base.copyWith(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: -0.1,
                color: selected ? selectedInk : unselectedInk,
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline success / error message. `liveRegion` lets screen readers announce
/// it the moment it appears.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.message,
    required this.isError,
    required this.colors,
  });

  final String message;
  final bool isError;
  final _AuthFormColors colors;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = isError ? scheme.error : colors.success;
    final background = isError
        ? (colors.isDark ? const Color(0xFF3A1918) : const Color(0xFFFDECEA))
        : colors.successFill;

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: foreground.withValues(alpha: 0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: 18,
              color: foreground,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The primary action. It inherits the mint/deep-green language of the
/// onboarding CTA, and sweeps a one-time highlight across itself as the card
/// arrives. The sweep then stops completely, so it costs nothing afterwards.
class _GradientButton extends StatefulWidget {
  const _GradientButton({
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.isDark,
    required this.onPressed,
  });

  final String label;
  final String busyLabel;
  final bool busy;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton>
    with SingleTickerProviderStateMixin {
  static const _darkInk = Color(0xFF04251C);

  late final AnimationController _sheen;
  bool _pressed = false;

  List<Color> get _gradient => widget.isDark
      ? const [Color(0xFF4ADE9B), Color(0xFF2FCB8C)]
      : const [Color(0xFF0F8A62), Color(0xFF0B7A55)];

  Color get _onGradient => widget.isDark ? _darkInk : Colors.white;

  @override
  void initState() {
    super.initState();
    _sheen = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return;
      _sheen.forward();
    });
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);

    return AnimatedScale(
      scale: _pressed ? 0.99 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _gradient,
          ),
          boxShadow: [
            BoxShadow(
              color: _gradient.last.withValues(
                alpha: widget.isDark ? 0.26 : 0.30,
              ),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _sheen,
                    builder: (context, child) {
                      final t = Curves.easeInOutCubic.transform(_sheen.value);
                      return FractionallySizedBox(
                        widthFactor: 0.45,
                        alignment: Alignment(-1.8 + 3.6 * t, 0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(alpha: 0.30),
                                Colors.white.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: radius,
                  onTap: widget.busy ? null : widget.onPressed,
                  onHighlightChanged: (value) =>
                      setState(() => _pressed = value),
                  splashColor: _onGradient.withValues(alpha: 0.10),
                  highlightColor: _onGradient.withValues(alpha: 0.06),
                  child: SizedBox(
                    height: 54,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        children: [
                          if (widget.busy) ...[
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: _onGradient,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                widget.busy ? widget.busyLabel : widget.label,
                                maxLines: 1,
                                style: TextStyle(
                                  color: _onGradient,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ),
                          if (!widget.busy) const SizedBox(width: 12),
                          if (!widget.busy)
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _onGradient.withValues(alpha: 0.14),
                              ),
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                size: 17,
                                color: _onGradient,
                              ),
                            ),
                        ],
                      ),
                    ),
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

class _CardFooter extends StatelessWidget {
  const _CardFooter({required this.colors});

  final _AuthFormColors colors;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.shield_outlined,
          size: 13,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Your details are only used to personalise your care.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: colors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Background// ═══════════════════════════════════════════════════════════════════════════

/// The emerald wash plus two very slow, very soft light pools. Nothing here
/// rebuilds the form: each glow only updates a `Transform`, and the whole
/// layer sits behind a `RepaintBoundary`.
class _AuthBackdrop extends StatelessWidget {
  const _AuthBackdrop({required this.palette, required this.animation});

  final MamaHeroColors palette;
  final Animation<double> animation;

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
              colors: [palette.top, palette.mid, palette.bottom],
              stops: const [0.0, 0.52, 1.0],
            ),
          ),
        ),

        // A whisper of a veil keeps white body copy comfortable to read on
        // the brighter top of the light-mode gradient. Dark mode is already
        // deep enough, so it leaves it alone.
        if (!palette.isDark)
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.08),
            ),
          ),

        // Two thin, almost invisible rings add an editorial sense of depth
        // without competing with the content.
        Positioned(
          top: -120,
          right: -140,
          child: IgnorePointer(
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.055),
                  width: 1.2,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: -190,
          right: -210,
          child: IgnorePointer(
            child: Container(
              width: 520,
              height: 520,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.035),
                ),
              ),
            ),
          ),
        ),

        Positioned(
          top: -170,
          right: -130,
          child: _FloatingGlow(
            animation: animation,
            phase: 0.0,
            drift: const Offset(24, 18),
            child: _Glow(size: 400, color: palette.glow, opacity: 0.20),
          ),
        ),
        Positioned(
          bottom: -250,
          left: -180,
          child: _FloatingGlow(
            animation: animation,
            phase: 0.5,
            drift: const Offset(28, 22),
            child: _Glow(size: 500, color: palette.glow2, opacity: 0.16),
          ),
        ),
      ],
    );
  }
}

/// Moves a pre-built glow around slowly. The child is created once, so each
/// frame only recalculates a translation matrix.
class _FloatingGlow extends StatelessWidget {
  const _FloatingGlow({
    required this.animation,
    required this.phase,
    required this.drift,
    required this.child,
  });

  final Animation<double> animation;
  final double phase;
  final Offset drift;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: IgnorePointer(child: child),
      builder: (context, child) {
        final t = (animation.value + phase) * 2 * math.pi;
        return Transform.translate(
          offset: Offset(math.sin(t) * drift.dx, math.cos(t + 1.4) * drift.dy),
          child: child,
        );
      },
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
    return Container(
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
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Theme-aware colours for the form sheet
// ═══════════════════════════════════════════════════════════════════════════

/// All the colours below live in one place so the card, fields, tabs and
/// notes stay in step in both themes. This is the only "design system" this
/// one screen needs.
class _AuthFormColors {
  const _AuthFormColors({required this.isDark});

  final bool isDark;

  /// The form sheet: pure white in light mode, soft green-charcoal in dark.
  List<Color> get card => isDark
      ? const [Color(0xFF16211C), Color(0xFF0F1713)]
      : const [Color(0xFFFFFFFF), Color(0xFFF8FBF9)];

  /// The 1px gradient edge that catches the light.
  List<Color> get cardEdge => isDark
      ? [
          Colors.white.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.06),
        ]
      : [
          Colors.white.withValues(alpha: 0.78),
          Colors.white.withValues(alpha: 0.20),
        ];

  Color get fieldFill =>
      isDark ? const Color(0xFF1C2822) : const Color(0xFFF3F7F4);
  Color get fieldBorder =>
      isDark ? const Color(0xFF2B3A33) : const Color(0xFFE2ECE7);
  Color get ink => isDark ? const Color(0xFFE9F4EF) : const Color(0xFF122018);
  Color get muted => isDark ? const Color(0xFF9DB0A7) : const Color(0xFF62716A);
  Color get accent =>
      isDark ? const Color(0xFF4ADE9B) : const Color(0xFF0B7A55);
  Color get tabTrack =>
      isDark ? const Color(0xFF1A2520) : const Color(0xFFEFF4F1);
  Color get tabTrackBorder =>
      isDark ? const Color(0xFF26332D) : const Color(0xFFE0E9E4);
  Color get menu => isDark ? const Color(0xFF1C2822) : Colors.white;
  Color get success =>
      isDark ? const Color(0xFF6EE7B7) : const Color(0xFF0B7A55);
  Color get successFill =>
      isDark ? const Color(0xFF10291F) : const Color(0xFFE9F9F1);
}
