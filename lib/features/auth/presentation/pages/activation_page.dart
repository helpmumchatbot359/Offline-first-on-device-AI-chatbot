import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/mama_background.dart';
import '../../../../core/widgets/mama_logo.dart';
import '../bloc/auth_bloc.dart';
import '../events/auth_event.dart';
import '../states/auth_state.dart';

/// Shown after a successful sign-up: the account exists but is still waiting
/// for the 6-digit code the backend emailed. Only the *pending* token is on
/// the phone at this point, so this screen is the only way forward.
class ActivationPage extends StatefulWidget {
  const ActivationPage({super.key});

  @override
  State<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends State<ActivationPage> {
  /// The backend's example code is 6 digits. Kept in one place so a future
  /// change is a one-line edit.
  static const int _codeLength = 6;

  /// The server accepts a code for 10 minutes after it was sent.
  static const Duration _codeLifetime = Duration(minutes: 10);

  /// Small pause before another "send a new code" tap is allowed. The server
  /// has no lockout, so this is purely to stop accidental spam.
  static const Duration _resendCooldown = Duration(seconds: 45);

  final _controller = TextEditingController();
  final _focus = FocusNode();

  Timer? _ticker;
  DateTime? _expiresAt;
  Duration _remaining = Duration.zero;
  DateTime? _cooldownUntil;

  /// Stops the same 6 digits from being submitted twice while the request runs.
  bool _autoSubmitted = false;

  int _lastResendCount = 0;

  @override
  void initState() {
    super.initState();

    final state = context.read<AuthBloc>().state;
    _expiresAt = state.pendingExpiresAt ?? DateTime.now().add(_codeLifetime);
    _remaining = _remainingNow();
    _lastResendCount = state.resendCount;

    _controller.addListener(_handleCodeChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining = _remainingNow();
        if (_cooldownUntil != null &&
            !DateTime.now().isBefore(_cooldownUntil!)) {
          _cooldownUntil = null;
        }
      });
    });

    // Open the keyboard straight away: the person is here to type a code.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.removeListener(_handleCodeChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Duration _remainingNow() {
    final expires = _expiresAt;
    if (expires == null) return Duration.zero;
    final left = expires.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get _expired => _remaining == Duration.zero;

  void _handleCodeChanged() {
    final code = _controller.text;
    setState(() {});

    if (code.length < _codeLength) {
      _autoSubmitted = false;
      return;
    }
    // Auto-submit once the sixth digit is in.
    if (code.length == _codeLength && !_autoSubmitted) {
      _autoSubmitted = true;
      _submit();
    }
  }

  void _submit() {
    final state = context.read<AuthBloc>().state;
    if (state.busy || _expired) return;
    if (_controller.text.length != _codeLength) return;

    FocusScope.of(context).unfocus();
    context.read<AuthBloc>().add(ActivationCodeSubmitted(_controller.text));
  }

  void _resend() {
    final now = DateTime.now();
    if (_cooldownUntil != null && now.isBefore(_cooldownUntil!)) return;

    setState(() {
      _cooldownUntil = now.add(_resendCooldown);
      _autoSubmitted = false;
      _controller.clear();
    });
    context.read<AuthBloc>().add(ActivationCodeResendRequested());
  }

  void _abandon() {
    context.read<AuthBloc>().add(ActivationAbandoned());
  }

  void _onState(BuildContext context, AuthState state) {
    if (state.resendCount != _lastResendCount) {
      _lastResendCount = state.resendCount;
      setState(() {
        _expiresAt = state.pendingExpiresAt ?? DateTime.now().add(_codeLifetime);
        _remaining = _remainingNow();
        _autoSubmitted = false;
        _controller.clear();
      });
      _focus.requestFocus();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('A new code is on its way.')),
        );
    }

    // Wrong/expired code: clear the boxes so the person can type again.
    if (state.error != null && state.status == AuthStatus.pendingActivation) {
      setState(() {
        _autoSubmitted = false;
        _controller.clear();
      });
      _focus.requestFocus();
    }
  }

  static String _clock(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MamaBackground(
        child: SafeArea(
          child: BlocConsumer<AuthBloc, AuthState>(
            listenWhen: (previous, current) =>
                previous.error != current.error ||
                previous.resendCount != current.resendCount,
            listener: _onState,
            builder: (context, state) {
              final email = (state.email ?? '').trim();
              final busy = state.busy;
              final code = _controller.text;
              final cooldownLeft = _cooldownUntil == null
                  ? 0
                  : _cooldownUntil!.difference(DateTime.now()).inSeconds;
              final canSubmit =
                  !busy && !_expired && code.length == _codeLength;

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: colors.outlineVariant),
                        boxShadow: [
                          BoxShadow(
                            color: colors.shadow.withValues(alpha: 0.06),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const MamaLogo(size: 56),
                          const SizedBox(height: 18),
                          Text(
                            'Check your email',
                            textAlign: TextAlign.center,
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text.rich(
                            TextSpan(
                              text: 'We sent a 6-digit code to\n',
                              children: [
                                TextSpan(
                                  text: email.isEmpty ? 'your email' : email,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: colors.onSurface,
                                  ),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 26),
                          _buildCodeBoxes(
                            colors: colors,
                            hasError: state.error != null,
                          ),
                          const SizedBox(height: 14),
                          if (state.error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                state.error!,
                                textAlign: TextAlign.center,
                                style: textTheme.bodySmall?.copyWith(
                                  color: colors.error,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          Text(
                            _expired
                                ? 'This code has expired. Send a new one below.'
                                : 'Code expires in ${_clock(_remaining)}',
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall?.copyWith(
                              color: _expired
                                  ? colors.error
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: canSubmit ? _submit : null,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: busy
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: colors.onPrimary,
                                      ),
                                    )
                                  : const Text('Verify code'),
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: busy || cooldownLeft > 0
                                ? null
                                : _resend,
                            child: Text(
                              cooldownLeft > 0
                                  ? 'Send a new code in ${cooldownLeft}s'
                                  : 'Send a new code',
                            ),
                          ),
                          Text(
                            "Didn't get it? Check your spam folder.",
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: busy ? null : _abandon,
                            child: const Text('Use a different email'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCodeBoxes({
    required ColorScheme colors,
    required bool hasError,
  }) {
    final code = _controller.text;

    return Semantics(
      label: 'Verification code, ${code.length} of $_codeLength digits entered',
      textField: true,
      child: Stack(
        children: [
          Row(
            children: List.generate(_codeLength, (index) {
              final filled = index < code.length;
              final active = index == code.length && !_expired;
              final borderColor = hasError
                  ? colors.error
                  : active
                  ? colors.primary
                  : colors.outlineVariant;

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index == _codeLength - 1 ? 0 : 8,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: borderColor,
                        width: active || hasError ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      filled ? code[index] : '',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                    ),
                  ),
                ),
              );
            }),
          ),
          // One invisible field drives all six boxes. It keeps paste, autofill
          // and the system keyboard working without six focus nodes.
          Positioned.fill(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              showCursor: false,
              enableInteractiveSelection: false,
              style: const TextStyle(color: Colors.transparent, height: 1),
              cursorColor: Colors.transparent,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(_codeLength),
              ],
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
      ),
    );
  }
}
