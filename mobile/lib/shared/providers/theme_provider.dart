import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_providers.dart';

/// Holds the patient's appearance preference, persisted across restarts.
///
/// Three states rather than a switch. A binary toggle has to pick a starting
/// position, and whichever it picks is wrong for the person whose phone is set
/// the other way — and it permanently discards "follow my phone", which is
/// what most people want.
///
/// The choice is not cosmetic for this app's users. Many patients are 45+,
/// where cataract and presbyopia make light text on dark backgrounds bloom and
/// smear; for them dark mode is harder to read, not easier. Others read in bed
/// at night where a white screen is the problem. Only the patient knows.
///
/// Deliberately device-local and never sent to the server: the same patient may
/// want dark on a phone and light on a tablet. Language is synced because it
/// drives what language the assistant replies in; appearance has no server-side
/// meaning.
class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController(this._prefs) : super(_readInitial(_prefs));

  final SharedPreferences _prefs;
  static const _key = 'akd_theme_mode';

  static ThemeMode _readInitial(SharedPreferences prefs) {
    switch (prefs.getString(_key)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      // Anything else — unset, or a value written by an older build — opens
      // light. The screens are designed light-first, and a patient whose phone
      // happens to be in dark mode should not meet a different-looking app than
      // the one the clinic showed them. "System" is still selectable in Profile.
      default:
        return ThemeMode.light;
    }
  }

  static String _encode(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };

  Future<void> setMode(ThemeMode mode) async {
    if (mode == state) return;
    // State first: the whole app repaints on this frame, and a slow disk write
    // must not delay the visible change.
    state = mode;
    await _prefs.setString(_key, _encode(mode));
  }
}

final themeControllerProvider = StateNotifierProvider<ThemeController, ThemeMode>((ref) {
  return ThemeController(ref.watch(sharedPreferencesProvider));
});
