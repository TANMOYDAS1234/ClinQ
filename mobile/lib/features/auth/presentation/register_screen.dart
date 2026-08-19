import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // FilteringTextInputFormatter, LengthLimitingTextInputFormatter
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/utils/auth_validators.dart';
import '../../../core/utils/vitals_validators.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers/locale_provider.dart';
import '../../../shared/widgets/auth_kit.dart';
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
          email: _emailController.text.trim().isEmpty
              ? null
              : _emailController.text.trim(),
          language: language,
          dateOfBirth: _dateOfBirth == null
              ? null
              : '${_dateOfBirth!.year.toString().padLeft(4, '0')}-'
                    '${_dateOfBirth!.month.toString().padLeft(2, '0')}-'
                    '${_dateOfBirth!.day.toString().padLeft(2, '0')}',
          gender: _gender,
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          heightCm: double.tryParse(_heightController.text.trim()),
          weightKg: double.tryParse(_weightController.text.trim()),
          systolic: int.tryParse(_systolicController.text.trim()),
          diastolic: int.tryParse(_diastolicController.text.trim()),
          pulse: int.tryParse(_pulseController.text.trim()),
          spo2: int.tryParse(_spo2Controller.text.trim()),
          glucoseMgDl: int.tryParse(_sugarController.text.trim()),
          complaints: _complaintsController.text.trim().isEmpty
              ? null
              : _complaintsController.text.trim(),
          inviteCode: _inviteController.text.trim().isEmpty
              ? null
              : _inviteController.text.trim(),
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

  /// An optional numeric vitals field with a unit suffix and a range validator.
  Widget _vital(
    TextEditingController c,
    String label,
    String unit,
    String? Function(String?) validator, {
    bool integer = false,
  }) {
    return AuthField(
      label: label,
      child: TextFormField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: !integer),
        style: T.body.copyWith(color: T.ink),
        inputFormatters: [
          integer
              ? FilteringTextInputFormatter.digitsOnly
              : FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          LengthLimitingTextInputFormatter(6),
        ],
        decoration: AuthField.decoration(hint: unit),
        validator: validator,
      ),
    );
  }

  Widget _section(String title, {String? note}) => Padding(
        padding: const EdgeInsets.only(top: T.s8, bottom: T.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(title, style: T.title.copyWith(color: T.ink)),
            if (note != null) ...[
              const SizedBox(width: T.s2),
              Text(note, style: T.small.copyWith(color: T.inkFaint)),
            ],
          ],
        ),
      );

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
              Padding(
                padding: const EdgeInsets.fromLTRB(T.s3, T.s2, T.s5, 0),
                child: Row(
                  children: [
                    CircleBack(onTap: () => context.go('/login')),
                    const SizedBox(width: T.s3),
                    // Progress, even though this is one page: it tells someone
                    // filling a long form that it is finite.
                    const Expanded(child: StepBar(step: 1, total: 2)),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(T.s5, T.s6, T.s5, T.s6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ScreenHeading(
                        title: l10n.authRegisterTitle,
                        subtitle: l10n.authRegisterSubtitle,
                      ),

                      _section('Your details'),

                      AuthField(
                        label: l10n.authNameLabel,
                        child: TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          style: T.body.copyWith(color: T.ink),
                          decoration: AuthField.decoration(hint: 'Full name'),
                          // The server enforces a 2-character minimum; mirror
                          // it here so a single-letter name fails locally
                          // instead of costing a round trip.
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return l10n.commonRequiredField;
                            }
                            if (v.trim().length < AuthValidators.minNameLength) {
                              return l10n.authNameTooShort;
                            }
                            if (v.trim().length > AuthValidators.maxNameLength) {
                              return l10n.authNameTooLong;
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: T.s5),

                      AuthField(
                        label: l10n.authPhoneLabel,
                        child: TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: T.body.copyWith(color: T.ink),
                          // One limiter, in the formatters. maxLength enforces
                          // after them and rewrites the value, resetting the
                          // caret to the end mid-edit. See the login screen.
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: AuthField.decoration(
                            hint: l10n.authPhoneHint,
                            prefixText: '${AuthValidators.countryCode} ',
                          ),
                          validator: (v) =>
                              (v == null || !AuthValidators.isValidPhone(v))
                                  ? l10n.authInvalidPhone
                                  : null,
                        ),
                      ),
                      const SizedBox(height: T.s5),

                      AuthField(
                        label: l10n.authEmailLabel,
                        child: TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: T.body.copyWith(color: T.ink),
                          decoration: AuthField.decoration(hint: 'Optional'),
                          // Optional field — but if they typed something, the
                          // server will reject anything that is not real.
                          validator: (v) => (v == null ||
                                  v.trim().isEmpty ||
                                  AuthValidators.isValidEmail(v))
                              ? null
                              : l10n.authInvalidEmail,
                        ),
                      ),

                      _section('Password'),

                      AuthField(
                        label: l10n.authPasswordLabel,
                        child: TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: T.body.copyWith(color: T.ink),
                          decoration: AuthField.decoration(
                            hint: l10n.authPasswordHint,
                            helper: l10n.authPasswordHelper,
                            suffix: IconButton(
                              iconSize: 20,
                              color: T.inkMuted,
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          // Re-validate only the confirmation field, so a
                          // corrected password clears the stale mismatch below
                          // it. Validating the whole form here would light up
                          // every other field mid-typing — `validate()` shows
                          // errors regardless of autovalidateMode.
                          onChanged: (_) {
                            if (_autovalidateMode != AutovalidateMode.disabled &&
                                _confirmPasswordController.text.isNotEmpty) {
                              _confirmPasswordKey.currentState?.validate();
                            }
                          },
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return l10n.authPasswordRequired;
                            }
                            if (v.length < AuthValidators.minPasswordLength) {
                              return l10n.authPasswordTooShort;
                            }
                            if (v.length > AuthValidators.maxPasswordLength) {
                              return l10n.authPasswordTooLong;
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: T.s5),

                      // There is no password-reset endpoint anywhere in the
                      // API, so a typo here locks the patient out of their
                      // account permanently. Confirming it is the only
                      // safeguard available.
                      AuthField(
                        label: l10n.authConfirmPasswordLabel,
                        child: TextFormField(
                          key: _confirmPasswordKey,
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          style: T.body.copyWith(color: T.ink),
                          decoration: AuthField.decoration(
                            hint: 'Type it again',
                            suffix: IconButton(
                              iconSize: 20,
                              color: T.inkMuted,
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setState(
                                () => _obscureConfirmPassword =
                                    !_obscureConfirmPassword,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return l10n.authPasswordRequired;
                            }
                            if (v != _passwordController.text) {
                              return l10n.authPasswordMismatch;
                            }
                            return null;
                          },
                        ),
                      ),

                      _section('About you'),

                      // A plain InkWell cannot participate in Form validation,
                      // so the date sits inside a FormField that owns the
                      // error state.
                      FormField<DateTime>(
                        initialValue: _dateOfBirth,
                        validator: (v) {
                          if (v == null) return l10n.authDateOfBirthRequired;
                          if (!AuthValidators.isPlausibleDateOfBirth(v)) {
                            return l10n.authDateOfBirthTooYoung;
                          }
                          return null;
                        },
                        builder: (field) => AuthField(
                          label: l10n.authDateOfBirthLabel,
                          child: InkWell(
                            onTap: () async {
                              await _pickDateOfBirth();
                              field.didChange(_dateOfBirth);
                            },
                            borderRadius: BorderRadius.circular(T.rCard),
                            child: InputDecorator(
                              decoration: AuthField.decoration(
                                suffix: const Icon(
                                  Icons.calendar_today_outlined,
                                  size: 20,
                                  color: T.inkMuted,
                                ),
                              ).copyWith(errorText: field.errorText),
                              child: Text(
                                _dateOfBirth == null
                                    ? 'Select date'
                                    : '${_dateOfBirth!.day.toString().padLeft(2, '0')}'
                                        '/${_dateOfBirth!.month.toString().padLeft(2, '0')}'
                                        '/${_dateOfBirth!.year}',
                                style: T.body.copyWith(
                                  color: _dateOfBirth == null
                                      ? T.inkFaint
                                      : T.ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: T.s5),

                      AuthField(
                        label: l10n.authGenderLabel,
                        child: DropdownButtonFormField<String>(
                          initialValue: _gender,
                          style: T.body.copyWith(color: T.ink),
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: T.inkMuted,
                          ),
                          decoration: AuthField.decoration(hint: 'Select'),
                          // The server also accepts 'undisclosed' (and defaults
                          // to it), but the form does not offer it — the field
                          // is required, so a patient always picks one of these
                          // three explicitly.
                          items: [
                            DropdownMenuItem(
                              value: 'male',
                              child: Text(l10n.authGenderMale),
                            ),
                            DropdownMenuItem(
                              value: 'female',
                              child: Text(l10n.authGenderFemale),
                            ),
                            DropdownMenuItem(
                              value: 'other',
                              child: Text(l10n.authGenderOther),
                            ),
                          ],
                          validator: (v) =>
                              v == null ? l10n.authGenderRequired : null,
                          onChanged: (v) => setState(() => _gender = v),
                        ),
                      ),
                      const SizedBox(height: T.s5),

                      AuthField(
                        label: 'Address',
                        child: TextFormField(
                          controller: _addressController,
                          textCapitalization: TextCapitalization.sentences,
                          minLines: 2,
                          maxLines: 3,
                          style: T.body.copyWith(color: T.ink),
                          decoration: AuthField.decoration(
                            hint: 'Where you live',
                          ),
                          // Required for a patient sign-up; a clinic-staff /
                          // dietician onboarding (invite code present) does
                          // not need one.
                          validator: (v) {
                            if (_inviteController.text.trim().isNotEmpty) {
                              return null;
                            }
                            if (v == null || v.trim().isEmpty) {
                              return 'Enter your address';
                            }
                            return null;
                          },
                        ),
                      ),

                      _section('Health details', note: 'optional'),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _vital(_heightController, 'Height', 'cm',
                                VitalsValidators.height),
                          ),
                          const SizedBox(width: T.s3),
                          Expanded(
                            child: _vital(_weightController, 'Weight', 'kg',
                                VitalsValidators.weight),
                          ),
                        ],
                      ),
                      const SizedBox(height: T.s5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _vital(_systolicController, 'BP systolic',
                                'mmHg', VitalsValidators.systolic,
                                integer: true),
                          ),
                          const SizedBox(width: T.s3),
                          Expanded(
                            child: _vital(
                              _diastolicController,
                              'BP diastolic',
                              'mmHg',
                              (v) => VitalsValidators.diastolic(
                                v,
                                systolicText: _systolicController.text,
                              ),
                              integer: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: T.s5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _vital(_pulseController, 'Heart rate', 'bpm',
                                VitalsValidators.pulse, integer: true),
                          ),
                          const SizedBox(width: T.s3),
                          Expanded(
                            child: _vital(_spo2Controller, 'SpO₂', '%',
                                VitalsValidators.spo2, integer: true),
                          ),
                        ],
                      ),
                      const SizedBox(height: T.s5),
                      _vital(_sugarController, 'Blood sugar', 'mg/dL',
                          VitalsValidators.sugar, integer: true),

                      _section('Anything else', note: 'optional'),

                      AuthField(
                        label: 'Main complaint',
                        child: TextFormField(
                          controller: _complaintsController,
                          textCapitalization: TextCapitalization.sentences,
                          minLines: 2,
                          maxLines: 3,
                          style: T.body.copyWith(color: T.ink),
                          decoration: AuthField.decoration(
                            hint: 'What brings you to the clinic',
                          ),
                        ),
                      ),
                      const SizedBox(height: T.s5),

                      AuthField(
                        label: 'Clinic code',
                        child: TextFormField(
                          controller: _inviteController,
                          textCapitalization: TextCapitalization.characters,
                          style: T.body.copyWith(color: T.ink),
                          decoration: AuthField.decoration(
                            hint: 'Only for clinic staff or dietician',
                          ),
                        ),
                      ),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: T.s6),
                        InlineError(message: _errorMessage!),
                      ],
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, T.s4),
                child: Column(
                  children: [
                    PillButton(
                      label: l10n.authRegisterButton,
                      loading: _isSubmitting,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: T.s4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          l10n.authHaveAccount,
                          style: T.small.copyWith(color: T.inkMuted),
                        ),
                        const SizedBox(width: T.s1),
                        GestureDetector(
                          onTap: () => context.go('/login'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: T.s2),
                            child: Text(
                              l10n.authGoToLogin,
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
