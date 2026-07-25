import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper over local notifications for short, in-the-moment updates
/// (an appointment confirmed, a clinic message). Delivered by the OS, so they
/// appear in the tray whether the app is in the foreground or the background.
///
/// This is deliberately *local* notifications, not server push: it needs no
/// Firebase project and shows the moment the app handles an event. True
/// closed-app push would need FCM wired to the backend.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _id = 0;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'clinq_updates',
    'ClinQ updates',
    description: 'Appointments and messages from the clinic',
    importance: Importance.high,
  );

  /// Safe to call more than once; the first call does the work.
  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);

    final android_ = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android_?.createNotificationChannel(_channel);
    // Android 13+ requires an explicit runtime permission for notifications.
    await android_?.requestNotificationsPermission();
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
}
