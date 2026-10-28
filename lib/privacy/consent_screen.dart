import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/privacy/consent_providers.dart';
import 'package:route_monitor/privacy/consent_repository.dart';

/// First-login consent gate (LGPD, RNF10). The router holds an authenticated
/// user here until they accept the current notice or sign out.
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _isSubmitting = false;

  Future<void> _accept() async {
    setState(() => _isSubmitting = true);
    try {
      await ref.read(consentRepositoryProvider).accept();
      ref.read(sessionProvider.notifier).clearConsentRequirement();
      ref.invalidate(consentStatusProvider);
      if (mounted) context.go('/rota');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _exit() async {
    await ref.read(sessionProvider.notifier).logout();
    if (mounted) context.go('/entrar');
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(consentStatusProvider);
    return Scaffold(
      body: SafeArea(
        child: status.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(AppStrings.consentLoadError),
            ),
          ),
          data: (data) => _ConsentBody(
            status: data,
            isSubmitting: _isSubmitting,
            onAccept: _accept,
            onExit: _exit,
          ),
        ),
      ),
    );
  }
}

class _ConsentBody extends StatelessWidget {
  const _ConsentBody({
    required this.status,
    required this.isSubmitting,
    required this.onAccept,
    required this.onExit,
  });

  final ConsentStatus status;
  final bool isSubmitting;
  final VoidCallback onAccept;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            status.noticeTitle ?? AppStrings.consentTitle,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Text(status.noticeBody ?? AppStrings.consentBody),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: isSubmitting ? null : onAccept,
            child: const Text(AppStrings.consentAcceptButton),
          ),
          TextButton(
            onPressed: isSubmitting ? null : onExit,
            child: const Text(AppStrings.consentExitButton),
          ),
        ],
      ),
    );
  }
}
