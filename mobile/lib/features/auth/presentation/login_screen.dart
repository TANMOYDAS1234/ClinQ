import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // FilteringTextInputFormatter, LengthLimitingTextInputFormatter
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/auth_validators.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers/locale_provider.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/error_view.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  /// Hidden until the first submit attempt — see the note in
  /// `RegisterScreen`; the two forms behave identically.
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Makes the account's stored language match the language the app is being
  /// used in.
  ///
  /// The first-run picker runs before login, so it can only set the local
  /// locale — the account keeps whatever language it was created with. Left
  /// alone, the two drift apart, and anything that reads `user.language`
  /// server-side (the doctor's dashboard, notification copy, the reply
  /// language when a client omits it) uses the stale value.
  ///
  /// Best-effort: a failure here must never block a successful login.
  Future<void> _reconcileLanguage() async {
    final appLanguage = ref.read(localeControllerProvider)?.languageCode;
    if (appLanguage == null || !supportedLanguageCodes.contains(appLanguage)) return;
    if (ref.read(authControllerProvider).user?.language == appLanguage) return;

    ref.read(authControllerProvider.notifier).updateLocalUserLanguage(appLanguage);
    try {
      await ref.read(authRepositoryProvider).updateMe(language: appLanguage);
    } on ApiException {
      // Local state is already correct; the server copy will catch up on the
      // next successful profile update.
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _autovalidateMode = AutovalidateMode.onUserInteraction);
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final error = await ref
        .read(authControllerProvider.notifier)
        .login(
          phone: AuthValidators.toE164(_phoneController.text),
          password: _passwordController.text,
        );

    if (error == null) await _reconcileLanguage();
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (error != null) {
      setState(() {
        _errorMessage = error.code == 'UNAUTHORIZED' || error.code == 'BAD_REQUEST'
            ? l10n.authInvalidCredentials
            : ErrorView.messageFor(context, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            autovalidateMode: _autovalidateMode,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.xl),
                const AppLogo(size: 72, showShadow: true),
                const SizedBox(height: AppSpacing.lg),
                Text(l10n.authLoginTitle, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(l10n.authLoginSubtitle, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.xl),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  // +91 is fixed and the patient types only the 10 national
                  // digits, so the field is locked to at most 10 digits.
                  maxLength: 10,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: InputDecoration(
                    labelText: l10n.authPhoneLabel,
                    hintText: l10n.authPhoneHint,
                    prefixIcon: const Icon(Icons.phone_outlined),
                    // The country code shows first, by default, always.
                    prefixText: '${AuthValidators.countryCode} ',
                    counterText: '',
                  ),
                  validator: (value) {
                    if (value == null || !AuthValidators.isValidPhone(value)) {
                      return l10n.authInvalidPhone;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: l10n.authPasswordLabel,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  onFieldSubmitted: (_) => _submit(),
                  // Only checks that something was typed. Enforcing the 8-char
                  // registration minimum here would be wrong twice over: the
                  // server accepts any non-empty password on login, and telling
                  // someone their *existing* password is "too short" reads as a
                  // rule about the account rather than a typo in the box.
                  validator: (value) =>
                      (value == null || value.isEmpty) ? l10n.authPasswordRequired : null,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.dangerBg,
                      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 16),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                AppButton(label: l10n.authLoginButton, isLoading: _isSubmitting, onPressed: _submit),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      Text(l10n.authNoAccount, style: Theme.of(context).textTheme.bodyMedium),
                      TextButton(
                        onPressed: () => context.go('/register'),
                        child: Text(l10n.authGoToRegister),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
