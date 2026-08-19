import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // FilteringTextInputFormatter, LengthLimitingTextInputFormatter
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/auth_validators.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers/locale_provider.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/auth_kit.dart';
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
    if (appLanguage == null || !supportedLanguageCodes.contains(appLanguage)) {
      return;
    }
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
      backgroundColor: T.surface,
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: _autovalidateMode,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(T.s5, T.s8, T.s5, T.s6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: AppLogo(size: 64)),
                      const SizedBox(height: T.s6),
                      ScreenHeading(
                        title: AppConfig.appName,
                        subtitle: l10n.authLoginSubtitle,
                        center: true,
                      ),
                      const SizedBox(height: T.s8),

                      AuthField(
                        label: l10n.authPhoneLabel,
                        child: TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          style: T.body.copyWith(color: T.ink),
                          // +91 is fixed and the patient types only the 10
                          // national digits.
                          //
                          // Capped by a formatter rather than maxLength.
                          // maxLength enforces AFTER the formatters and
                          // rewrites the whole value, which resets the
                          // selection — so tapping into the middle of a full
                          // number and typing threw the cursor to the end. The
                          // formatter preserves the caret. Exactly one limiter,
                          // always: two of them fight and reintroduce the jump.
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: AuthField.decoration(
                            hint: l10n.authPhoneHint,
                            prefixText: '${AuthValidators.countryCode} ',
                          ),
                          validator: (value) {
                            if (value == null ||
                                !AuthValidators.isValidPhone(value)) {
                              return l10n.authInvalidPhone;
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: T.s5),

                      AuthField(
                        label: l10n.authPasswordLabel,
                        child: TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          autofillHints: const [AutofillHints.password],
                          style: T.body.copyWith(color: T.ink),
                          decoration: AuthField.decoration(
                            hint: l10n.authPasswordHint,
                            suffix: IconButton(
                              iconSize: 20,
                              color: T.inkMuted,
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              tooltip: _obscurePassword ? 'Show' : 'Hide',
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          onFieldSubmitted: (_) => _submit(),
                          // Only checks that something was typed. Enforcing the
                          // 8-char registration minimum here would be wrong
                          // twice over: the server accepts any non-empty
                          // password on login, and telling someone their
                          // *existing* password is "too short" reads as a rule
                          // about the account rather than a typo in the box.
                          validator: (value) => (value == null || value.isEmpty)
                              ? l10n.authPasswordRequired
                              : null,
                        ),
                      ),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: T.s5),
                        InlineError(message: _errorMessage!),
                      ],
                    ],
                  ),
                ),
              ),

              // The action sits against the bottom of the screen rather than
              // after the last field: it is always in the same place and
              // always in reach, whatever the form above it is doing.
              Padding(
                padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, T.s4),
                child: Column(
                  children: [
                    PillButton(
                      label: l10n.authLoginButton,
                      loading: _isSubmitting,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: T.s4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          l10n.authNoAccount,
                          style: T.small.copyWith(color: T.inkMuted),
                        ),
                        const SizedBox(width: T.s1),
                        GestureDetector(
                          onTap: () => context.go('/register'),
                          child: Padding(
                            // Padding, not a bare tap: the words alone are a
                            // 16px-tall target.
                            padding: const EdgeInsets.symmetric(vertical: T.s2),
                            child: Text(
                              l10n.authGoToRegister,
                              style: T.small.copyWith(
                                color: T.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
