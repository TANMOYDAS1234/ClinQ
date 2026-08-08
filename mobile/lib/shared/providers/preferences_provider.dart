import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_providers.dart';

/// Glucose display unit. India uses mg/dL almost universally, but patients who
/// trained abroad or use imported meters read mmol/L — so it is a preference.
enum GlucoseUnit {
  mgdl('mg/dL'),
  mmol('mmol/L');

  const GlucoseUnit(this.label);
  final String label;

  /// mg/dL ÷ 18.0182 = mmol/L.
  static const double _factor = 18.0182;

  /// Convert a stored mg/dL value into this unit, rounded for display.
  double fromMgdl(num mgdl) => this == GlucoseUnit.mgdl ? mgdl.toDouble() : mgdl / _factor;

  /// Format a stored mg/dL value in this unit — whole numbers for mg/dL, one
  /// decimal for mmol/L, with the unit appended.
  String format(num mgdl, {bool withUnit = true}) {
    final v = fromMgdl(mgdl);
    final text = this == GlucoseUnit.mgdl ? v.round().toString() : v.toStringAsFixed(1);
    return withUnit ? '$text $label' : text;
  }
}

/// Device-local app preferences that are neither theme nor language: the
/// glucose unit and the notification toggles. Persisted in SharedPreferences,
/// mirroring [ThemeController].
///
/// The notification toggles record the patient's intent. Delivery is still
/// stubbed server-side (see notifications.js), so today they gate nothing on
/// the wire — but they are the switch the push transport will read once wired,
/// and honest to show rather than hide.
class AppPreferences {
  const AppPreferences({
    this.glucoseUnit = GlucoseUnit.mgdl,
    this.medicationReminders = true,
    this.checkInReminders = true,
    this.appointmentAlerts = true,
    this.clinicAlerts = true,
  });

  final GlucoseUnit glucoseUnit;
  final bool medicationReminders;
  final bool checkInReminders;
  final bool appointmentAlerts;
  final bool clinicAlerts;

  AppPreferences copyWith({
    GlucoseUnit? glucoseUnit,
    bool? medicationReminders,
    bool? checkInReminders,
    bool? appointmentAlerts,
    bool? clinicAlerts,
  }) => AppPreferences(
    glucoseUnit: glucoseUnit ?? this.glucoseUnit,
    medicationReminders: medicationReminders ?? this.medicationReminders,
    checkInReminders: checkInReminders ?? this.checkInReminders,
    appointmentAlerts: appointmentAlerts ?? this.appointmentAlerts,
    clinicAlerts: clinicAlerts ?? this.clinicAlerts,
  );
}

class AppPreferencesController extends StateNotifier<AppPreferences> {
  AppPreferencesController(this._prefs) : super(_read(_prefs));

  final SharedPreferences _prefs;

  static const _unitKey = 'akd_glucose_unit';
  static const _medKey = 'akd_notif_medication';
  static const _checkInKey = 'akd_notif_checkin';
  static const _apptKey = 'akd_notif_appointment';
  static const _clinicKey = 'akd_notif_clinic';

  static AppPreferences _read(SharedPreferences p) => AppPreferences(
    glucoseUnit: p.getString(_unitKey) == 'mmol' ? GlucoseUnit.mmol : GlucoseUnit.mgdl,
    medicationReminders: p.getBool(_medKey) ?? true,
    checkInReminders: p.getBool(_checkInKey) ?? true,
    appointmentAlerts: p.getBool(_apptKey) ?? true,
    clinicAlerts: p.getBool(_clinicKey) ?? true,
  );

  Future<void> setGlucoseUnit(GlucoseUnit unit) async {
    state = state.copyWith(glucoseUnit: unit);
    await _prefs.setString(_unitKey, unit == GlucoseUnit.mmol ? 'mmol' : 'mgdl');
  }

  Future<void> setMedicationReminders(bool v) async {
    state = state.copyWith(medicationReminders: v);
    await _prefs.setBool(_medKey, v);
  }

  Future<void> setCheckInReminders(bool v) async {
    state = state.copyWith(checkInReminders: v);
    await _prefs.setBool(_checkInKey, v);
  }

  Future<void> setAppointmentAlerts(bool v) async {
    state = state.copyWith(appointmentAlerts: v);
    await _prefs.setBool(_apptKey, v);
  }

  Future<void> setClinicAlerts(bool v) async {
    state = state.copyWith(clinicAlerts: v);
    await _prefs.setBool(_clinicKey, v);
  }
}

final appPreferencesProvider =
    StateNotifierProvider<AppPreferencesController, AppPreferences>((ref) {
  return AppPreferencesController(ref.watch(sharedPreferencesProvider));
});

/// Convenience selector for the glucose unit alone.
final glucoseUnitProvider = Provider<GlucoseUnit>((ref) {
  return ref.watch(appPreferencesProvider).glucoseUnit;
});
