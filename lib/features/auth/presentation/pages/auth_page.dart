import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/auth_bloc.dart';
import '../events/auth_event.dart';
import '../states/auth_state.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, this.initialSignIn = true});

  final bool initialSignIn;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  late bool _isSignIn;

  // Global key to manage and validate form state
  final _formKey = GlobalKey<FormState>();

  // Controllers to read input values
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _genderController = TextEditingController();
  final _countryController = TextEditingController();

  // Regex pattern for standard email format verification
  static final RegExp _emailRegExp = RegExp(
    r'^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+',
  );

  @override
  void initState() {
    super.initState();
    _isSignIn = widget.initialSignIn;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _genderController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  void _submit(BuildContext context) {
    // 1. Run form validators across all text fields
    if (!_formKey.currentState!.validate()) {
      return; // Stop submission if validation fails
    }

    final authBloc = context.read<AuthBloc>();

    // 2. Dispatch events to AuthBloc if validation passes
    if (_isSignIn) {
      authBloc.add(SignInSubmitted(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      ));
    } else {
      authBloc.add(SignUpSubmitted(
        username: _usernameController.text.trim(),
        gender: _genderController.text.trim(),
        email: _emailController.text.trim(),
        country: _countryController.text.trim(),
        password: _passwordController.text.trim(),
      ));
    }
  }

  // Helper widget to construct field labels with red asterisks
  Widget _buildRequiredLabel(String labelText, ColorScheme colorScheme) {
    return RichText(
      text: TextSpan(
        text: labelText,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 16,
        ),
        children: [
          TextSpan(
            text: ' *',
            style: TextStyle(
              color: colorScheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSignIn ? 'Welcome Back' : 'Create Account'),
      ),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.error!)),
            );
          }
        },
        builder: (context, state) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    _isSignIn
                        ? 'Sign in to continue to MamaBot'
                        : 'Join MamaBot for personalized health guidance',
                    style: TextStyle(
                      fontSize: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Extra fields for Sign Up only
                  if (!_isSignIn) ...[
                    TextFormField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        label: _buildRequiredLabel('Username', colorScheme),
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Username is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _genderController,
                      decoration: InputDecoration(
                        label: _buildRequiredLabel(
                          'Gender (e.g., Female, Male)',
                          colorScheme,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please specify your gender';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _countryController,
                      decoration: InputDecoration(
                        label: _buildRequiredLabel(
                          'Country (e.g., Nigeria)',
                          colorScheme,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Country is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Common fields (Email and Password)
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      label: _buildRequiredLabel('Email Address', colorScheme),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Email address is required';
                      }
                      if (!_emailRegExp.hasMatch(value.trim())) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      label: _buildRequiredLabel('Password', colorScheme),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Password is required';
                      }
                      if (value.trim().length < 6) {
                        return 'Password must be at least 6 characters long';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Submit Button
                  FilledButton(
                    onPressed: state.busy ? null : () => _submit(context),
                    child: state.busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isSignIn ? 'Sign In' : 'Sign Up'),
                  ),
                  const SizedBox(height: 16),

                  // Toggle Sign In / Sign Up Mode
                  TextButton(
                    onPressed: () {
                      _formKey.currentState?.reset();
                      setState(() {
                        _isSignIn = !_isSignIn;
                      });
                    },
                    child: Text(
                      _isSignIn
                          ? "Don't have an account? Sign Up"
                          : "Already have an account? Sign In",
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}