import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/privacy/consent_providers.dart';
import 'package:route_monitor/privacy/consent_repository.dart';

/// Self-registration of a field worker (spec 2026-10-20-alocacao-automatica
/// §9): name, e-mail, password, company and acceptance of the current privacy
/// notice. The account waits for a manager's approval; the acceptance here
/// stands in for the post-login consent screen.
class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  // Same bounds as the backend's RegisterRequest.
  static const _minPasswordLength = 8;
  static const _maxPasswordLength = 128;
  static const _maxNameLength = 200;
  // `local@domain.tld`: the backend's EmailStr refuses a domain without a
  // dot (`ana@gmail`), and that typo must be caught here, not as a 422.
  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$');

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _companyId;
  bool _noticeAccepted = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit(PrivacyNotice notice) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .register(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
            companyId: _companyId!,
            noticeVersion: notice.version,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(content: Text(AppStrings.registrationSent)),
      );
      context.go('/entrar');
    } on EmailTakenException {
      _showError(AppStrings.registrationEmailTaken);
    } on NoticeOutdatedException {
      // A new notice was published meanwhile: show it and ask again.
      if (!mounted) return;
      ref.invalidate(currentNoticeProvider);
      _noticeAccepted = false;
      _showError(AppStrings.registrationNoticeOutdated);
    } on UnknownCompanyException {
      // Removed while the form was open: reload the list, choose again.
      if (!mounted) return;
      ref.invalidate(publicCompaniesProvider);
      _companyId = null;
      _showError(AppStrings.registrationCompanyGone);
    } on InvalidRegistrationException {
      _showError(AppStrings.registrationInvalidData);
    } on DioException catch (error) {
      // Only a failure with no response is the connection's fault.
      _showError(
        error.response == null
            ? AppStrings.registrationError
            : AppStrings.registrationServerError,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    if (mounted) setState(() => _errorMessage = message);
  }

  void _retryLoading() {
    ref
      ..invalidate(publicCompaniesProvider)
      ..invalidate(currentNoticeProvider);
  }

  @override
  Widget build(BuildContext context) {
    final companies = ref.watch(publicCompaniesProvider);
    final notice = ref.watch(currentNoticeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.registrationTitle)),
      body: SafeArea(
        child: switch ((companies, notice)) {
          (AsyncData(value: final companies), AsyncData(value: final notice)) =>
            _buildForm(companies, notice),
          (AsyncError(), _) || (_, AsyncError()) => _LoadError(
            onRetry: _retryLoading,
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _buildForm(List<CompanyOption> companies, PrivacyNotice notice) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ..._accountFields(companies),
            const SizedBox(height: 24),
            _NoticePanel(notice: notice),
            CheckboxListTile(
              key: const Key('registration-accept'),
              value: _noticeAccepted,
              onChanged: _isSubmitting
                  ? null
                  : (value) => setState(() => _noticeAccepted = value ?? false),
              title: const Text(AppStrings.registrationAcceptNotice),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('registration-submit'),
              onPressed: _noticeAccepted && !_isSubmitting
                  ? () => _submit(notice)
                  : null,
              child: Text(
                _isSubmitting
                    ? AppStrings.registrationSubmitting
                    : AppStrings.registrationSubmit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Counted in code points (`runes`), the way the backend's `len()` counts,
  /// not in UTF-16 units (`length`) or graphemes. No input formatter caps it:
  /// silently truncating a password would leave the worker unable to log in.
  static String? _validatePassword(String? value) {
    final codePoints = (value ?? '').runes.length;
    if (codePoints < _minPasswordLength) {
      return AppStrings.registrationPasswordTooShort;
    }
    if (codePoints > _maxPasswordLength) {
      return AppStrings.registrationPasswordTooLong;
    }
    return null;
  }

  List<Widget> _accountFields(List<CompanyOption> companies) => [
    TextFormField(
      key: const Key('registration-name'),
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: AppStrings.registrationNameLabel,
      ),
      textCapitalization: TextCapitalization.words,
      inputFormatters: [LengthLimitingTextInputFormatter(_maxNameLength)],
      validator: (value) => (value ?? '').trim().isEmpty
          ? AppStrings.registrationNameRequired
          : null,
    ),
    const SizedBox(height: 12),
    TextFormField(
      key: const Key('registration-email'),
      controller: _emailController,
      decoration: const InputDecoration(
        labelText: AppStrings.registrationEmailLabel,
      ),
      keyboardType: TextInputType.emailAddress,
      validator: (value) => _emailShape.hasMatch((value ?? '').trim())
          ? null
          : AppStrings.registrationEmailInvalid,
    ),
    const SizedBox(height: 12),
    TextFormField(
      key: const Key('registration-password'),
      controller: _passwordController,
      decoration: const InputDecoration(
        labelText: AppStrings.registrationPasswordLabel,
      ),
      obscureText: true,
      validator: _validatePassword,
    ),
    const SizedBox(height: 12),
    DropdownButtonFormField<String>(
      key: const Key('registration-company'),
      initialValue: _companyId,
      decoration: const InputDecoration(
        labelText: AppStrings.registrationCompanyLabel,
      ),
      items: [
        for (final company in companies)
          DropdownMenuItem(value: company.id, child: Text(company.name)),
      ],
      onChanged: (value) => setState(() => _companyId = value),
      validator: (value) =>
          value == null ? AppStrings.registrationCompanyRequired : null,
    ),
  ];
}

/// The notice the worker accepts: title, version, and the text in its own
/// scroll box so the form stays reachable below a long notice.
class _NoticePanel extends StatelessWidget {
  const _NoticePanel({required this.notice});

  final PrivacyNotice notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(notice.title, style: theme.textTheme.titleMedium),
        Text(
          AppStrings.registrationNoticeVersion(notice.version),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Text(notice.body),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(AppStrings.registrationLoadError),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text(AppStrings.registrationRetry),
            ),
          ],
        ),
      ),
    );
  }
}
