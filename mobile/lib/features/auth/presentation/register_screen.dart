import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // FilteringTextInputFormatter, LengthLimitingTextInputFormatter
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/auth_validators.dart';
import '../../../core/utils/vitals_validators.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers/locale_provider.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/error_view.dart';
import 'auth_controller.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _addressController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _pulseController = TextEditingController();
  final _spo2Controller = TextEditingController();
  final _sugarController = TextEditingController();
  final _complaintsController = TextEditingController();
  final _inviteController = TextEditingController();

  /// Errors stay hidden until the first submit attempt. `onUserInteraction`
  /// validates the *whole* form as soon as any single field is touched, so
  /// typing the first character of a name turned every remaining field red
  /// while the patient was still filling it in. After a failed submit this
  /// flips to live validation so corrections clear as they are made.
  final _confirmPasswordKey = GlobalKey<FormFieldState<String>>();
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  DateTime? _dateOfBirth;
  String? _gender;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _addressController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _pulseController.dispose();
    _spo2Controller.dispose();
    _sugarController.dispose();
    _complaintsController.dispose();
    _inviteController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 45, now.month, now.day),
      firstDate: DateTime(now.year - 110),
      lastDate: now,
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  /// An optional numeric vitals field with a unit suffix and a range validator.
  Widget _vital(
    TextEditingController c,
    String label,
    String unit,
    String? Function(String?) validator, {
    bool integer = false,
  }) {
    return TextFormField(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: !integer),
      inputFormatters: [
        integer
            ? FilteringTextInputFormatter.digitsOnly
            : FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        LengthLimitingTextInputFormatter(6),
      ],
      decoration: InputDecoration(labelText: label, suffixText: unit),
      validator: validator,
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      // First failed submit: from here on, errors track typing so a corrected
      // field clears immediately instead of waiting for another submit.
      setState(() => _autovalidateMode = AutovalidateMode.onUserInteraction);
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final language = ref.read(localeControllerProvider)?.languageCode ?? 'en';
    final error = await ref
        .read(authControllerProvider.notifier)
        .register(
          name: _nameController.text.trim(),
          phone: AuthValidators.toE164(_phoneController.text),
          password: _passwordController.text,
          email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
          language: language,
          dateOfBirth: _dateOfBirth == null
              ? null
              : '${_dateOfBirth!.year.toString().padLeft(4, '0')}-'
                    '${_dateOfBirth!.month.toString().padLeft(2, '0')}-'
                    '${_dateOfBirth!.day.toString().padLeft(2, '0')}',
          gender: _gender,
          address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
          heightCm: double.tryParse(_heightController.text.trim()),
          weightKg: double.tryParse(_weightController.text.trim()),
          systolic: int.tryParse(_systolicController.text.trim()),
          diastolic: int.tryParse(_diastolicController.text.trim()),
          pulse: int.tryParse(_pulseController.text.trim()),
          spo2: int.tryParse(_spo2Controller.text.trim()),
          glucoseMgDl: int.tryParse(_sugarController.text.trim()),
          complaints: _complaintsController.text.trim().isEmpty ? null : _complaintsController.text.trim(),
          inviteCode: _inviteController.text.trim().isEmpty ? null : _inviteController.text.trim(),
          // Deliberately not sent from this screen — diabetes type is no
          // longer collected at signup. The server therefore applies its
          // `.default('type2')`, so it must be confirmed with the patient
          // before any type-dependent advice is relied on. The repository
          // still accepts the field for whichever screen collects it later.
        );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (error != null) {
      setState(() => _errorMessage = ErrorView.messageFor(context, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.authRegisterTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          // Narrower side padding so the fields run wider across the screen.
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.lg),
          child: Form(
            key: _formKey,
            autovalidateMode: _autovalidateMode,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.md),
                // Same brand block as sign-in, so the two screens read as one
                // product rather than a styled entry and a plain form.
                const Center(child: AppLogo(size: 64, showShadow: true)),
                const SizedBox(height: AppSpacing.md),
                Text(
                  AppConfig.appName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accentOn(context),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.authRegisterSubtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: l10n.authNameLabel,
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                  ),
                  // The server enforces a 2-character minimum; mirror it here
                  // so a single-letter name fails locally instead of costing a
                  // round trip.
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return l10n.commonRequiredField;
                    if (v.trim().length < AuthValidators.minNameLength) {
                      return l10n.authNameTooShort;
                    }
                    if (v.trim().length > AuthValidators.maxNameLength) {
                      return l10n.authNameTooLong;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  // One limiter, in the formatters. maxLength enforces after
                  // them and rewrites the value, resetting the caret to the end
                  // mid-edit. See the login screen.
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: InputDecoration(
                    labelText: l10n.authPhoneLabel,
                    hintText: l10n.authPhoneHint,
                    prefixIcon: const Icon(Icons.phone_outlined),
                    // +91 shown first, by default.
                    prefixText: '${AuthValidators.countryCode} ',
                    counterText: '',
                  ),
                  validator: (v) =>
                      (v == null || !AuthValidators.isValidPhone(v)) ? l10n.authInvalidPhone : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: l10n.authEmailLabel,
                    prefixIcon: const Icon(Icons.mail_outline_rounded),
                  ),
                  // Optional field — but if they typed something, the server
                  // will reject anything that is not a real address.
                  validator: (v) => (v == null || v.trim().isEmpty || AuthValidators.isValidEmail(v))
                      ? null
                      : l10n.authInvalidEmail,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: l10n.authPasswordLabel,
                    // State the rule before they type, not after they fail.
                    helperText: l10n.authPasswordHelper,
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
                  // Re-validate only the confirmation field, so a corrected
                  // password clears the stale mismatch below it. Validating the
                  // whole form here would light up every other field mid-typing
                  // — `validate()` shows errors regardless of autovalidateMode.
                  onChanged: (_) {
                    if (_autovalidateMode != AutovalidateMode.disabled &&
                        _confirmPasswordController.text.isNotEmpty) {
                      _confirmPasswordKey.currentState?.validate();
                    }
                  },
                  validator: (v) {
                    if (v == null || v.isEmpty) return l10n.authPasswordRequired;
                    if (v.length < AuthValidators.minPasswordLength) {
                      return l10n.authPasswordTooShort;
                    }
                    if (v.length > AuthValidators.maxPasswordLength) {
                      return l10n.authPasswordTooLong;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                // There is no password-reset endpoint anywhere in the API, so a
                // typo here locks the patient out of their account permanently.
                // Confirming it is the only safeguard available.
                TextFormField(
                  key: _confirmPasswordKey,
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: l10n.authConfirmPasswordLabel,
                    prefixIcon: const Icon(Icons.lock_reset_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return l10n.authPasswordRequired;
                    if (v != _passwordController.text) return l10n.authPasswordMismatch;
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                // A plain InkWell cannot participate in Form validation, so the
                // date sits inside a FormField that owns the error state.
                FormField<DateTime>(
                  initialValue: _dateOfBirth,
                  validator: (v) {
                    if (v == null) return l10n.authDateOfBirthRequired;
                    if (!AuthValidators.isPlausibleDateOfBirth(v)) {
                      return l10n.authDateOfBirthTooYoung;
                    }
                    return null;
                  },
                  builder: (field) => InkWell(
                    onTap: () async {
                      await _pickDateOfBirth();
                      field.didChange(_dateOfBirth);
                    },
                    borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: l10n.authDateOfBirthLabel,
                        prefixIcon: const Icon(Icons.cake_outlined),
                        errorText: field.errorText,
                      ),
                      child: Text(
                        _dateOfBirth == null
                            ? '—'
                            : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: InputDecoration(
                    labelText: l10n.authGenderLabel,
                    prefixIcon: const Icon(Icons.wc_outlined),
                  ),
                  // The server also accepts 'undisclosed' (and defaults to it),
                  // but the form does not offer it — the field is required, so
                  // a patient always picks one of these three explicitly.
                  items: [
                    DropdownMenuItem(value: 'male', child: Text(l10n.authGenderMale)),
                    DropdownMenuItem(value: 'female', child: Text(l10n.authGenderFemale)),
                    DropdownMenuItem(value: 'other', child: Text(l10n.authGenderOther)),
                  ],
                  validator: (v) => v == null ? l10n.authGenderRequired : null,
                  onChanged: (v) => setState(() => _gender = v),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _addressController,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.home_outlined),
                  ),
                  // Required for a patient sign-up; a clinic-staff / dietician
                  // onboarding (invite code present) does not need one.
                  validator: (v) {
                    if (_inviteController.text.trim().isNotEmpty) return null;
                    if (v == null || v.trim().isEmpty) return 'Enter your address';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Health details (optional)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: _vital(_heightController, 'Height', 'cm', VitalsValidators.height)),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: _vital(_weightController, 'Weight', 'kg', VitalsValidators.weight)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(child: _vital(_systolicController, 'BP systolic', 'mmHg', VitalsValidators.systolic, integer: true)),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _vital(
                        _diastolicController,
                        'BP diastolic',
                        'mmHg',
                        (v) => VitalsValidators.diastolic(v, systolicText: _systolicController.text),
                        integer: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(child: _vital(_pulseController, 'Heart rate', 'bpm', VitalsValidators.pulse, integer: true)),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: _vital(_spo2Controller, 'SpO₂', '%', VitalsValidators.spo2, integer: true)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _vital(_sugarController, 'Blood sugar', 'mg/dL', VitalsValidators.sugar, integer: true),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _complaintsController,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Complaints (optional)',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.assignment_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _inviteController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Clinic code (optional)',
                    helperText: 'Only for clinic staff / dietician onboarding',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.dangerBgOn(context),
                      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: AppColors.dangerOn(context), fontSize: 16),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: l10n.authRegisterButton,
                  isLoading: _isSubmitting,
                  onPressed: _submit,
                ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(l10n.authHaveAccount, style: Theme.of(context).textTheme.bodyMedium),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: Text(
                          l10n.authGoToLogin,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
