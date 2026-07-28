import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// One dose reminder to schedule: a medicine name + a local clock time. The
/// medications feature flattens its `Medication.schedule` into these so this
/// service stays unaware of the API model.
class MedReminder {
  const MedReminder({
    required this.medId,
    required this.name,
    required this.time,
    this.dose,
    this.relationToMeal,
  });

  final String medId;
  final String name;

  /// "HH:mm" in the clinic's local time.
  final String time;
  final String? dose;
  final String? relationToMeal;
}

/// Local notifications: short in-the-moment updates via [show], and repeating
/// medication reminders via [scheduleMedicationReminders].
///
/// The medication reminders are *scheduled on the device* (Android exact
/// alarms), so "time to take your medicine" fires at the right minute even when
/// the app is closed or the phone has been idle — no server, push, or network
/// needed at reminder time.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _id = 0;

  /// Medication reminder ids live in a reserved range so cancelling/replacing
  /// the whole set never touches the ids [show] hands out.
  static const int _medIdBase = 700000;
  static const int _medIdSpan = 100000;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'clinq_updates',
    'ClinQ updates',
    description: 'Appointments and messages from the clinic',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _medsChannel = AndroidNotificationChannel(
    'clinq_meds',
    'Medication reminders',
    description: 'Reminds you when it is time to take a medicine',
    importance: Importance.max,
  );

  /// Safe to call more than once; the first call does the work.
  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);

    final android_ = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android_?.createNotificationChannel(_channel);
    await android_?.createNotificationChannel(_medsChannel);
    // Android 13+ requires an explicit runtime permission for notifications.
    await android_?.requestNotificationsPermission();
    // Android 12+ gate for exact alarms. A medicine reminder that fires whenever
    // Doze next wakes is useless, so we ask for exact timing.
    await android_?.requestExactAlarmsPermission();

    tz_data.initializeTimeZones();
    // The clinic and its patients are in India; medication times are IST wall
    // clock. Pinning the zone keeps reminders correct without a native
    // timezone plugin.
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    _ready = true;
  }

  /// Show a notification now. Keep [title]/[body] short and specific.
  Future<void> show({required String title, required String body}) async {
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'clinq_updates',
        'ClinQ updates',
        channelDescription: 'Appointments and messages from the clinic',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    _id = (_id + 1) % 100000;
    await _plugin.show(_id, title, body, details);
  }

  /// Rebuilds the full set of daily medication reminders from [reminders].
  ///
  /// Cancels the previous set first, so stopping or re-timing a medicine takes
  /// effect immediately. Each reminder repeats every day at its time (via
  /// [DateTimeComponents.time]) and survives reboot through the plugin's boot
  /// receiver. Idempotent — safe to call on every schedule change or app resume.
  Future<void> scheduleMedicationReminders(List<MedReminder> reminders) async {
    await init();

    // Drop the previous medication set (reserved id range only).
    for (final p in await _plugin.pendingNotificationRequests()) {
      if (p.id >= _medIdBase && p.id < _medIdBase + _medIdSpan) {
        await _plugin.cancel(p.id);
      }
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'clinq_meds',
        'Medication reminders',
        channelDescription: 'Reminds you when it is time to take a medicine',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.reminder,
      ),
    );

    var id = _medIdBase;
    for (final r in reminders) {
      final parts = r.time.split(':');
      if (parts.length != 2) continue;
      final hh = int.tryParse(parts[0]);
      final mm = int.tryParse(parts[1]);
      if (hh == null || mm == null || hh > 23 || mm > 59) continue;
      if (id >= _medIdBase + _medIdSpan) break; // safety cap

      try {
        await _plugin.zonedSchedule(
          id++,
          'Time to take ${r.name}',
          _reminderBody(r),
          _nextInstanceOf(hh, mm),
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          // iOS-only, but a required param; absolute time is what we schedule.
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time, // repeat daily
          payload: 'med:${r.medId}',
        );
      } catch (e) {
        // A single bad slot must not drop every other reminder.
        debugPrint('med reminder schedule failed for ${r.name} @ ${r.time}: $e');
      }
    }
  }

  /// Clears every scheduled medication reminder (e.g. on sign-out, so the next
  /// person on a shared phone isn't reminded about someone else's medicine).
  Future<void> cancelMedicationReminders() async {
    await init();
    for (final p in await _plugin.pendingNotificationRequests()) {
      if (p.id >= _medIdBase && p.id < _medIdBase + _medIdSpan) {
        await _plugin.cancel(p.id);
      }
    }
  }

  String _reminderBody(MedReminder r) {
    final bits = <String>[];
    if (r.dose != null && r.dose!.isNotEmpty) bits.add(r.dose!);
    final meal = _mealLabel(r.relationToMeal);
    if (meal != null) bits.add(meal);
    return bits.isEmpty ? 'Tap when taken' : bits.join(' · ');
  }

  String? _mealLabel(String? relation) {
    switch (relation) {
      case 'before_meal':
        return 'before food';
      case 'after_meal':
        return 'after food';
      case 'with_meal':
        return 'with food';
      default:
        return null;
    }
  }

  /// The next time [hh]:[mm] happens in local time — today if it is still ahead,
  /// otherwise tomorrow. The daily-repeat flag carries it forward after that.
  tz.TZDateTime _nextInstanceOf(int hh, int mm) {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hh, mm);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    return when;
  }
}
