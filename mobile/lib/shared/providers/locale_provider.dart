import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_providers.dart';

const supportedLanguageCodes = ['en', 'bn', 'hi'];

/// Which language the assistant must reply in.
///
/// The language the app is *currently displayed in* wins over the language
/// stored on the account. The two diverge routinely: the first-run picker runs
/// before login, so it can only set the local locale and leaves a seeded or
/// previously-chosen account language untouched.
///
/// Following the account instead produced the reported bug — an English UI
/// answering an English question in Bengali, because the demo account was
/// seeded `language: 'bn'`.
///
/// The server applies `req.body.language ?? req.user.language ?? 'en'`, so an
/// explicit value from the client is authoritative.
String resolveReplyLanguage({String? appLocale, String? accountLanguage}) {
  if (appLocale != null && supportedLanguageCodes.contains(appLocale)) return appLocale;
  if (accountLanguage != null && supportedLanguageCodes.contains(accountLanguage)) {
    return accountLanguage;
  }
  return 'en';
}

/// Holds the patient's chosen UI language. `null` means "not chosen yet",
/// which the router uses to decide whether the language-picker screen
/// should be shown on first launch. Once set, changing it (e.g. from the
/// Profile screen) updates the whole app's locale immediately.
class LocaleController extends StateNotifier<Locale?> {
  LocaleController(this._prefs) : super(_readInitial(_prefs));

  final SharedPreferences _prefs;
  static const _key = 'akd_language_code';

  static Locale? _readInitial(SharedPreferences prefs) {
    final code = prefs.getString(_key);
    if (code == null || !supportedLanguageCodes.contains(code)) return null;
    return Locale(code);
  }

  bool get hasChosenLanguage => state != null;

  Future<void> setLanguage(String code) async {
    if (!supportedLanguageCodes.contains(code)) return;
    await _prefs.setString(_key, code);
    state = Locale(code);
  }
}

final localeControllerProvider = StateNotifierProvider<LocaleController, Locale?>((ref) {
  return LocaleController(ref.watch(sharedPreferencesProvider));
});
