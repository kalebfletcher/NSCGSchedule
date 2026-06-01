import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:async';

enum NotificationType {
  lessonStart,
  minutesBefore,
  examStart,
  examMinutesBefore,
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Stream to request rescheduling from anywhere (e.g., Settings page)
  final StreamController<void> _rescheduleController =
      StreamController<void>.broadcast();
  Stream<void> get onReschedule => _rescheduleController.stream;
  void requestReschedule() {
    if (!_rescheduleController.isClosed) {
      _rescheduleController.add(null);
    }
  }

  Future<void> init({
    void Function(NotificationResponse response)?
    onDidReceiveNotificationResponse,
  }) async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestSoundPermission: false,
          requestBadgePermission: false,
          requestAlertPermission: false,
        );

    const LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    const WindowsInitializationSettings initializationSettingsWindows =
        WindowsInitializationSettings(
          appName: 'nscgschedule',
          appUserModelId: 'uk.bw86.nscgschedule',
          guid: 'bfc31329-0bd6-4e08-8d51-9b1c43dcb95b',
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
          macOS: initializationSettingsIOS,
          linux: initializationSettingsLinux,
          windows: initializationSettingsWindows,
        );

    tz.initializeTimeZones();

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );
  }

  Future<void> requestPermissions() async {
    final IOSFlutterLocalNotificationsPlugin? iosImplementation =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
    if (iosImplementation != null) {
      await iosImplementation.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
      await androidImplementation.requestExactAlarmsPermission();
    }
  }

  Future<void> scheduleNotification(
    int id,
    String title,
    String body,
    DateTime scheduledTime, {
    bool repeatWeekly = false,
    NotificationType type = NotificationType.lessonStart,
    String? payload,
  }) async {
    final isStartType =
        type == NotificationType.lessonStart ||
        type == NotificationType.examStart;
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(scheduledTime, tz.local),
      notificationDetails: NotificationDetails(
        android: isStartType
            ? const AndroidNotificationDetails(
                'lesson_start_channel',
                'Lesson Start',
                channelDescription: 'Notifications for when a lesson starts.',
                importance: Importance.max,
                priority: Priority.high,
                ticker: 'ticker',
              )
            : const AndroidNotificationDetails(
                'minutes_before_channel',
                'Upcoming Lesson',
                channelDescription: 'Notifications for an upcoming lesson.',
                importance: Importance.defaultImportance,
                priority: Priority.defaultPriority,
                ticker: 'ticker',
              ),
        iOS: DarwinNotificationDetails(
          sound: 'default.wav',
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: repeatWeekly
          ? DateTimeComponents.dayOfWeekAndTime
          : null,
    );
  }

  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  // Debug helpers
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await flutterLocalNotificationsPlugin.pendingNotificationRequests();
  }

  Future<void> scheduleTestNotification({int minutesFromNow = 1}) async {
    if (minutesFromNow < 0) minutesFromNow = 0;
    final when = DateTime.now().add(Duration(minutes: minutesFromNow));
    await scheduleNotification(
      999000 + minutesFromNow, // test notification ID space
      'Test notification',
      'This is a test scheduled in $minutesFromNow minute(s).',
      when,
    );
  }

  void dispose() {
    _rescheduleController.close();
  }
}
