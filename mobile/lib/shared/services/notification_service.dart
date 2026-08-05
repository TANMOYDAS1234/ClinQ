import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Handles a tap on a reminder's action button while the app is not running.
///
/// Android delivers these into a separate background isolate, so nothing from
/// the app's state is reachable here — the snooze re-schedules through a fresh
/// plugin instance rather than through [NotificationService].
@pragma('vm:entry-point')
void medicationActionHandler(NotificationResponse response) {
  if (response.actionId != NotificationService.snoozeActionId) return;
  final payload = response.payload;
  NotificationService.scheduleSnoozeFromBackground(payload);
}

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

  /// Invoked when the user taps a notification this service showed, with that
  /// notification's payload. Set by the push layer so a tap can open the right
  /// conversation. The payload is the FCM data map as JSON, or `med:<id>` for a
  /// medication reminder.
  void Function(String payload)? onNotificationTap;

  /// Medication reminder ids live in a reserved range so cancelling/replacing
  /// the whole set never touches the ids [show] hands out.
  static const int _medIdBase = 700000;
  static const int _medIdSpan = 100000;

  /// Snoozes sit outside the daily range so re-syncing the schedule (which
  /// cancels that whole range) does not silently drop a dose the patient just
  /// pushed back by ten minutes.
  static const int _snoozeIdBase = 900000;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'clinq_updates',
    'ClinQ updates',
    description: 'Appointments and messages from the clinic',
    importance: Importance.high,
  );

  /// Fires five minutes ahead of the dose so the patient can reach the medicine
  /// before it is due, rather than being told they are already late.
  static const Duration leadTime = Duration(minutes: 5);

  /// How long the alarm keeps ringing if nobody touches it. Long enough to be
  /// heard from another room, short enough not to wake a household when the
  /// patient is out — after this Android cancels it and the sound stops.
  static const Duration ringFor = Duration(minutes: 3);

  static const String stopActionId = 'med_stop';
  static const String snoozeActionId = 'med_snooze';
  static const Duration snoozeFor = Duration(minutes: 10);

  /// A *new* channel id, not a reworked `clinq_meds`.
  ///
  /// Android freezes a channel's sound and importance the first time it is
  /// created and ignores every later change, so a phone that already had the
  /// old quiet channel would have gone on chiming once however this code was
  /// written. Alarm usage also means the reminder follows the alarm volume,
  /// which is the one people leave up overnight.
  static const AndroidNotificationChannel _medsChannel = AndroidNotificationChannel(
    'clinq_meds_alarm',
    'Medication alarms',
    description: 'Rings when it is time to take a medicine',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );

  /// Safe to call more than once; the first call does the work.
  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings,
      // A tap on a notification we showed (a foreground push, or a med reminder)
      // routes through the push layer, which opens the relevant conversation.
      onDidReceiveNotificationResponse: (resp) {
        if (resp.actionId == snoozeActionId) {
          scheduleSnoozeFromBackground(resp.payload);
          return;
        }
        // Stop only needs the notification gone, which the action itself does.
        if (resp.actionId == stopActionId) return;
        final payload = resp.payload;
        if (payload != null && payload.isNotEmpty) onNotificationTap?.call(payload);
      },
      // Action taps while the app is dead arrive in a background isolate;
      // without this handler Stop and Snooze would do nothing outside the app.
      onDidReceiveBackgroundNotificationResponse: medicationActionHandler,
    );

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

  /// Show a notification now. Keep [title]/[body] short and specific. [payload]
  /// (an FCM data map as JSON) is handed back to [onNotificationTap] on tap, so
  /// the app can open the conversation the notification is about.
  Future<void> show({required String title, required String body, String? payload}) async {
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
    await _plugin.show(_id, title, body, details, payload: payload);
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

    final details = alarmDetails();

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
          '${r.name} in ${leadTime.inMinutes} minutes',
          _reminderBody(r),
          _nextInstanceOf(hh, mm).subtract(leadTime),
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

  /// The alarm-style presentation shared by the scheduled reminder and its
  /// snooze, so a snoozed dose rings exactly as the original did.
  ///
  /// `FLAG_INSISTENT` (4) is what makes it an alarm rather than a chime:
  /// Android repeats the sound until the notification goes away. [ringFor]
  /// bounds that, and the Stop action ends it immediately — one notification
  /// that rings until dismissed but cannot ring forever.
  static NotificationDetails alarmDetails() => NotificationDetails(
    android: AndroidNotificationDetails(
      'clinq_meds_alarm',
      'Medication alarms',
      channelDescription: 'Rings when it is time to take a medicine',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      // Deliberately NOT a full-screen intent. Android 14 gates that behind an
      // app-op it grants only to calling and alarm-clock apps; for everyone
      // else it rejects at post time and drops the notification entirely. The
      // reminder was being enqueued and then silently discarded. Importance.max
      // on an alarm channel already gives a heads-up banner over the lock
      // screen, which is what was actually wanted.
      additionalFlags: Int32List.fromList(<int>[4]), // FLAG_INSISTENT
      timeoutAfter: ringFor.inMilliseconds,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(<int>[0, 700, 500, 700, 500, 700]),
      // Dismissible by design: an alarm the patient cannot silence is one they
      // will turn off at the system level, losing every later dose with it.
      autoCancel: true,
      ongoing: false,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          stopActionId,
          'Stop',
          cancelNotification: true,
          showsUserInterface: false,
        ),
        AndroidNotificationAction(
          snoozeActionId,
          'Remind in ${snoozeFor.inMinutes} min',
          cancelNotification: true,
          showsUserInterface: false,
        ),
      ],
    ),
  );

  /// Re-rings a dose [snoozeFor] later, from the background isolate an action
  /// tap runs in. Uses its own plugin instance and its own id range, so it
  /// neither depends on app state nor collides with the daily set.
  static Future<void> scheduleSnoozeFromBackground(String? payload) async {
    final plugin = FlutterLocalNotificationsPlugin();
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    try {
      await plugin.zonedSchedule(
        _snoozeIdBase + tz.TZDateTime.now(tz.local).second,
        'Medicine reminder',
        'You snoozed this dose — take it now.',
        tz.TZDateTime.now(tz.local).add(snoozeFor),
        alarmDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (e) {
      debugPrint('snooze schedule failed: $e');
    }
  }

  String _reminderBody(MedReminder r) {
    final bits = <String>[];
    if (r.dose != null && r.dose!.isNotEmpty) bits.add(r.dose!);
    final meal = _mealLabel(r.relationToMeal);
    if (meal != null) bits.add(meal);
    // The dose time itself, because the alarm now rings before it: without it
    // "in 5 minutes" leaves the patient working out when that actually is.
    bits.add('at ${r.time}');
    return bits.join(' · ');
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
