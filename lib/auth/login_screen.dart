import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/l10n/strings.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;
  bool _isSubmitting = false;

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .login(
            email: _emailController.text,
            password: _passwordController.text,
          );
      if (mounted) context.go('/rota');
    } on InvalidCredentialsException {
      setState(() => _errorMessage = AppStrings.loginInvalidCredentials);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                AppStrings.loginBrand,
                style: TextStyle(letterSpacing: 1.2),
              ),
              const SizedBox(height: 4),
              const Text(
                AppStrings.loginTitle,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              TextField(
                key: const Key('email-field'),
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: AppStrings.loginEmailLabel,
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('password-field'),
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: AppStrings.loginPasswordLabel,
                ),
                obscureText: true,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('login-button'),
                onPressed: _isSubmitting ? null : _submit,
                child: Text(
                  _isSubmitting
                      ? AppStrings.loginSubmitting
                      : AppStrings.loginSubmitButton,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
