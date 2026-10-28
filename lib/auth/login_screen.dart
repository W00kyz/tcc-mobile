import 'package:dio/dio.dart';
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
    } on DioException {
      // Unreachable server (no signal, wrong LAN): say so instead of failing
      // silently with the button re-enabled.
      setState(() => _errorMessage = AppStrings.loginNetworkError);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// RF03: e-mails a reset link; the link opens the panel's reset page.
  Future<void> _forgotPassword() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) =>
          _ForgotPasswordDialog(initialEmail: _emailController.text),
    );
    if (email == null || email.trim().isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authRepositoryProvider).requestPasswordReset(email.trim());
      messenger.showSnackBar(
        const SnackBar(content: Text(AppStrings.forgotPasswordSent)),
      );
    } on DioException {
      messenger.showSnackBar(
        const SnackBar(content: Text(AppStrings.forgotPasswordError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // Scrolls so the open keyboard never overflows the form on a small
        // phone, now that "Criar conta" sits under it too.
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.loginBrand,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    letterSpacing: 1.2,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.loginTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('forgot-password-button'),
                  onPressed: _isSubmitting ? null : _forgotPassword,
                  child: const Text(AppStrings.loginForgotPassword),
                ),
                TextButton(
                  key: const Key('create-account-button'),
                  onPressed: _isSubmitting
                      ? null
                      : () => context.push('/cadastro'),
                  child: const Text(AppStrings.loginCreateAccount),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final _controller = TextEditingController(text: widget.initialEmail);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.forgotPasswordTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(AppStrings.forgotPasswordIntro),
          TextField(
            key: const Key('forgot-password-email'),
            controller: _controller,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: AppStrings.loginEmailLabel,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.forgotPasswordCancel),
        ),
        FilledButton(
          key: const Key('forgot-password-send'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text(AppStrings.forgotPasswordSend),
        ),
      ],
    );
  }
}
