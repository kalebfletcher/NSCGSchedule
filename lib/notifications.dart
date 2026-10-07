import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

enum NotificationType {
  lessonStart,
  minutesBefore,
  examStart,
  examMinutesBefore,
}

class ScheduledNotificationInfo {
  final DateTime scheduledAt;
  final bool repeatsWeekly;

  const ScheduledNotificationInfo({
    required this.scheduledAt,
    required this.repeatsWeekly,
  });
}

class NotificationService {
  static const String _scheduledNotificationInfoKey =
      'scheduled_notification_info';
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _localTimezoneReady = false;

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
    try {
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimezone.identifier));
      _localTimezoneReady = true;
    } catch (e) {
      debugPrint('Could not initialize the device timezone for notifications: $e');
      // Keep notifications available if the platform timezone plugin is missing
      // (for example, when a newly added native plugin has not been rebuilt).
      // timezone's initialized default is UTC, so one-off alarms retain their
      // intended instant. Weekly repeats may need a reschedule after timezone
      // initialization succeeds on the next full app restart.
      tz.setLocalLocation(tz.UTC);
      _localTimezoneReady = true;
    }

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
    if (!_localTimezoneReady) {
      // init normally sets this, but do not let a transient platform failure
      // prevent the notification plugin from accepting scheduled alarms.
      tz.setLocalLocation(tz.UTC);
      _localTimezoneReady = true;
    }
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

    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_scheduledNotificationInfoKey);
      final records = raw == null
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      records['$id'] = {
        'scheduledAt': scheduledTime.toIso8601String(),
        'repeatsWeekly': repeatWeekly,
      };
      await preferences.setString(
        _scheduledNotificationInfoKey,
        jsonEncode(records),
      );
    } catch (e) {
      debugPrint('Could not save notification schedule details: $e');
    }
  }

  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_scheduledNotificationInfoKey);
    } catch (e) {
      debugPrint('Could not clear notification schedule details: $e');
    }
  }

  // Debug helpers
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await flutterLocalNotificationsPlugin.pendingNotificationRequests();
  }

  Future<Map<int, ScheduledNotificationInfo>>
  getPendingNotificationScheduleInfo() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_scheduledNotificationInfoKey);
    if (raw == null) return {};

    try {
      final records = jsonDecode(raw) as Map<String, dynamic>;
      final result = <int, ScheduledNotificationInfo>{};
      for (final entry in records.entries) {
        final id = int.tryParse(entry.key);
        final value = entry.value;
        if (id == null || value is! Map) continue;
        final scheduledAt = DateTime.tryParse(
          value['scheduledAt'] as String? ?? '',
        );
        if (scheduledAt == null) continue;
        result[id] = ScheduledNotificationInfo(
          scheduledAt: scheduledAt,
          repeatsWeekly: value['repeatsWeekly'] as bool? ?? false,
        );
      }
      return result;
    } catch (_) {
      return {};
    }
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
