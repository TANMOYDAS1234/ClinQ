import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/gen/app_localizations.dart';

/// Full-screen (or in-place) error state with a retry action. Maps
/// [ApiException.code] to a localized, patient-friendly message.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, this.error, this.onRetry, this.title});

  final Object? error;
  final VoidCallback? onRetry;
  final String? title;

  static String messageFor(BuildContext context, Object? error) {
    final l10n = AppLocalizations.of(context);
    if (error is ApiException) {
      switch (error.code) {
        case 'BAD_REQUEST':
          return _withDetails(l10n.errorBadRequest, error);
        case 'VALIDATION_ERROR':
          return _withDetails(l10n.errorValidation, error);
        case 'UNAUTHORIZED':
          return l10n.errorUnauthorized;
        case 'FORBIDDEN':
          return l10n.errorForbidden;
        case 'NOT_FOUND':
          return l10n.errorNotFound;
        case 'CONFLICT':
          return l10n.errorConflict;
        case 'DUPLICATE':
          return l10n.errorDuplicate;
        case 'RATE_LIMITED':
          return l10n.errorRateLimited;
        case 'INVALID_ID':
          return l10n.errorInvalidId;
        case 'AI_UNAVAILABLE':
          return l10n.errorAiUnavailable;
        case 'NETWORK_ERROR':
        case 'TIMEOUT':
          return l10n.commonNoInternet;
        case 'INTERNAL_ERROR':
          return l10n.errorInternal;
        default:
          return l10n.commonUnknownError;
      }
    }
    return l10n.commonUnknownError;
  }

  /// A bare "check the details you entered" leaves the patient guessing which
  /// field the server rejected. The backend already names them in
  /// `error.details`, so append those rather than swallowing them.
  static String _withDetails(String base, ApiException error) {
    if (error.details.isEmpty) return base;
    final lines = error.details
        .map((d) => d.message)
        .where((m) => m.isNotEmpty)
        .toSet()
        .map((m) => '• $m');
    if (lines.isEmpty) return base;
    return '$base\n${lines.join('\n')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title ?? l10n.commonSomethingWentWrong,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              messageFor(context, error),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.commonRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
