import 'package:akd_care/core/utils/auth_validators.dart';
import 'package:akd_care/features/auth/presentation/login_screen.dart';
import 'package:akd_care/features/auth/presentation/register_screen.dart';
import 'package:akd_care/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Field-level validation for the two auth forms.
///
/// These assert the *client* rules stay at least as strict as the server's
/// (`backend/src/routes/auth.js`). A client rule looser than the server's turns
/// into an opaque VALIDATION_ERROR after a round trip; stricter is safe.
void main() {
  Widget harness(Widget screen) => ProviderScope(
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: screen,
    ),
  );

  Future<void> enter(WidgetTester tester, String label, String text) async {
    await tester.enterText(find.widgetWithText(TextFormField, label), text);
    await tester.pump();
  }

  /// The register form is taller than the default 800x600 test surface, so a
  /// plain `tap()` on the submit button silently misses (tap only *warns* when
  /// the hit test lands outside the viewport). Give the tests a phone-shaped
  /// surface tall enough to hold the whole form.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Errors are hidden until the first submit attempt, so most field-rule
  /// tests have to press the button once before anything is on screen.
  Future<void> submit(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ElevatedButton, label));
    await tester.pumpAndSettle();
  }

  group('AuthValidators', () {
    test('phone accepts 10-digit numbers starting 6-9', () {
      for (final ok in ['9830012345', '6000000000', '7412589630', '8888888888']) {
        expect(AuthValidators.isValidPhone(ok), isTrue, reason: ok);
      }
      for (final bad in ['5830012345', '983001234', '98300123456', '', 'abcdefghij']) {
        expect(AuthValidators.isValidPhone(bad), isFalse, reason: bad);
      }
    });

    test('phone strips punctuation before validating', () {
      expect(AuthValidators.isValidPhone('98300 12345'), isTrue);
      expect(AuthValidators.toE164('98300-12345'), '+919830012345');
    });

    test('email mirrors the server contract', () {
      expect(AuthValidators.isValidEmail('a@b.co'), isTrue);
      for (final bad in ['a@b', 'a b@c.com', '@b.com', 'plain']) {
        expect(AuthValidators.isValidEmail(bad), isFalse, reason: bad);
      }
    });

    test('bounds match the server schema', () {
      expect(AuthValidators.minPasswordLength, 8);
      expect(AuthValidators.maxPasswordLength, 128);
      expect(AuthValidators.minNameLength, 2);
      expect(AuthValidators.maxNameLength, 120);
    });

    test('enums cover every value the server accepts', () {
      expect(
        AuthValidators.diabetesTypes,
        containsAll(['type1', 'type2', 'gestational', 'prediabetes', 'none']),
      );
      expect(AuthValidators.genders, containsAll(['male', 'female', 'other', 'undisclosed']));
    });

    test('date of birth rejects the future, today, and implausible ages', () {
      final now = DateTime(2026, 7, 23);
      expect(AuthValidators.isPlausibleDateOfBirth(DateTime(1975, 4, 2), now: now), isTrue);
      expect(AuthValidators.isPlausibleDateOfBirth(DateTime(2027, 1, 1), now: now), isFalse);
      expect(AuthValidators.isPlausibleDateOfBirth(now, now: now), isFalse);
      expect(AuthValidators.isPlausibleDateOfBirth(DateTime(1850, 1, 1), now: now), isFalse);
    });
  });

  group('Login form', () {
    testWidgets('shows nothing until the button is pressed', (tester) async {
      await tester.pumpWidget(harness(const LoginScreen()));
      await tester.pumpAndSettle();

      await enter(tester, 'Phone number', '98300');
      expect(find.text('Enter a valid 10-digit mobile number'), findsNothing);
      expect(find.text('Please enter your password'), findsNothing);

      await submit(tester, 'Log in');
      expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
    });

    testWidgets('rejects a 9-digit number and one starting below 6', (tester) async {
      await tester.pumpWidget(harness(const LoginScreen()));
      await tester.pumpAndSettle();
      await submit(tester, 'Log in');

      await enter(tester, 'Phone number', '983001234');
      expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);

      await enter(tester, 'Phone number', '5830012345');
      expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);

      await enter(tester, 'Phone number', '9830012345');
      expect(find.text('Enter a valid 10-digit mobile number'), findsNothing);
    });

    testWidgets('does not impose the 8-char registration rule on an existing password', (
      tester,
    ) async {
      await tester.pumpWidget(harness(const LoginScreen()));
      await tester.pumpAndSettle();
      await submit(tester, 'Log in');

      // The server accepts any non-empty password on login.
      await enter(tester, 'Password', 'short');
      expect(find.text('Password must be at least 8 characters'), findsNothing);
      expect(find.text('Please enter your password'), findsNothing);
    });
  });

  group('Register form', () {
    testWidgets('typing in one field does not turn the rest of the form red', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(const RegisterScreen()));
      await tester.pumpAndSettle();

      // The reported bug: `AutovalidateMode.onUserInteraction` validates the
      // whole form on the first keystroke, so entering a name lit up phone,
      // password, confirm, date of birth and gender all at once.
      await enter(tester, 'Full name', 'Tanm');

      for (final error in [
        'Enter a valid 10-digit mobile number',
        'Please enter your password',
        'Please select your date of birth',
        'Please select an option',
      ]) {
        expect(find.text(error), findsNothing, reason: 'shown while still typing: $error');
      }
    });

    testWidgets('blocks submit until every required field is answered', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(const RegisterScreen()));
      await tester.pumpAndSettle();

      await submit(tester, 'Create account');

      expect(find.text('Please select your date of birth'), findsOneWidget);
      expect(find.text('Please select an option'), findsOneWidget);
    });

    testWidgets('after a failed submit, fixing a field clears its error live', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(const RegisterScreen()));
      await tester.pumpAndSettle();

      await submit(tester, 'Create account');
      expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);

      await enter(tester, 'Phone number', '9830012345');
      expect(find.text('Enter a valid 10-digit mobile number'), findsNothing);
    });

    testWidgets('does not ask for diabetes type at signup', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(const RegisterScreen()));
      await tester.pumpAndSettle();

      // Removed by request. Note the consequence: the server applies
      // `.default('type2')` to an omitted diabetesType, so whichever screen
      // collects it later must confirm it before type-dependent advice is
      // trusted. Gender remains the only dropdown on the form.
      expect(find.text('Diabetes type'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('offers exactly three gender options', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(const RegisterScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      for (final label in ['Male', 'Female', 'Other']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      // Removed by request. The server still accepts (and defaults to)
      // 'undisclosed', but the field is required so a choice is always made.
      expect(find.text('Prefer not to say'), findsNothing);
    });

    testWidgets('catches a mistyped password confirmation', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(const RegisterScreen()));
      await tester.pumpAndSettle();
      await submit(tester, 'Create account');

      await enter(tester, 'Password', 'Patient@1234');
      await enter(tester, 'Confirm password', 'Patient@1235');
      expect(find.text('Passwords do not match'), findsOneWidget);

      await enter(tester, 'Confirm password', 'Patient@1234');
      expect(find.text('Passwords do not match'), findsNothing);
    });

    testWidgets('correcting the first password clears a stale mismatch', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(const RegisterScreen()));
      await tester.pumpAndSettle();
      await submit(tester, 'Create account');

      await enter(tester, 'Password', 'Patient@1234');
      await enter(tester, 'Confirm password', 'Patient@9999');
      expect(find.text('Passwords do not match'), findsOneWidget);

      // Fixing the *upper* field must re-run the confirmation's validator.
      await enter(tester, 'Password', 'Patient@9999');
      expect(find.text('Passwords do not match'), findsNothing);
    });

    testWidgets('enforces name and password bounds', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(const RegisterScreen()));
      await tester.pumpAndSettle();
      await submit(tester, 'Create account');

      await enter(tester, 'Full name', 'A');
      expect(find.text('Please enter your full name'), findsOneWidget);

      await enter(tester, 'Full name', 'A' * 121);
      expect(find.text('Name must be 120 characters or fewer'), findsOneWidget);

      await enter(tester, 'Full name', 'Rahul Das');
      expect(find.text('Please enter your full name'), findsNothing);

      await enter(tester, 'Password', 'short');
      expect(find.text('Password must be at least 8 characters'), findsOneWidget);

      await enter(tester, 'Password', 'x' * 129);
      expect(find.text('Password must be 128 characters or fewer'), findsOneWidget);
    });

    testWidgets('email is optional but validated when present', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(const RegisterScreen()));
      await tester.pumpAndSettle();
      await submit(tester, 'Create account');

      await enter(tester, 'Email (optional)', 'not-an-email');
      expect(find.text('Enter a valid email address, or leave it blank'), findsOneWidget);

      await enter(tester, 'Email (optional)', '');
      expect(find.text('Enter a valid email address, or leave it blank'), findsNothing);

      await enter(tester, 'Email (optional)', 'rahul@example.com');
      expect(find.text('Enter a valid email address, or leave it blank'), findsNothing);
    });
  });
}
