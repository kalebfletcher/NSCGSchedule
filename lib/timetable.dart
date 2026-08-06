import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:intl/intl.dart';
import 'package:nscgschedule/models/timetable_models.dart' as models;
import 'package:nscgschedule/models/exam_models.dart';
import 'package:nscgschedule/requests.dart';
import 'package:nscgschedule/settings.dart';
import 'package:nscgschedule/notifications.dart';
import 'package:get_it/get_it.dart';
import 'package:nscgschedule/debug_service.dart';

// Enable interactive room editing with: --dart-define=INSERT_ROOM_NUMBERS=true
const bool kInsertRoomNumbers = bool.fromEnvironment(
  'INSERT_ROOM_NUMBERS',
  defaultValue: false,
);

class TimetableScreen extends StatefulWidget {
  final String? initialDay;
  final int? highlightLessonIndex;

  const TimetableScreen({
    super.key,
    this.initialDay,
    this.highlightLessonIndex,
  });

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  final CookieManager _cookieManager = CookieManager.instance();
  final NSCGRequests _requests = NSCGRequests.instance;
  bool _isLoading = true;
  String _error = '';
  models.Timetable? _timetable;
  String _timetableUpdated = '';
  bool _loggedin = false;
  Timer? _timer;
  String _timeRemaining = '';
  String? _nextLessonId; // Track which lesson should show the countdown
  final NotificationService _notificationService =
      GetIt.I<NotificationService>();
  // Set to true to enable debug mode with simulated times
  bool _debugMode = false;
  StreamSubscription<void>? _resub;
  StreamSubscription<bool>? _debugSub;
  StreamSubscription<bool>? _updateSub;
  StreamSubscription<bool>? _loggedinSub;
  StreamSubscription<void>? _notificationResub;
  int? _highlightLessonIndex;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    _loadTimetable();
    init();
    _startTimer();

    // Handle deep link highlight
    if (widget.highlightLessonIndex != null) {
      _highlightLessonIndex = widget.highlightLessonIndex;
      // Clear highlight after 3 seconds
      _highlightTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _highlightLessonIndex = null;
          });
        }
      });
    }

    // Listen for notification settings changes to reschedule notifications
    _resub = settings.onNotificationSettingsChanged.listen((_) {
      _scheduleNotifications();
    });

    _notificationResub = _notificationService.onReschedule.listen((_) {
      if (mounted) _scheduleNotifications();
    });

    _debugSub = _requests.debugModeController.stream.listen((value) {
      if (mounted) {
        setState(() {
          _debugMode = value;
        });
      }
    });

    _updateSub = _requests.updateController.stream.listen((value) {
      if (mounted) {
        setState(() {});
      }
    });

    _loggedinSub = _requests.loggedinController.stream.listen((value) {
      if (mounted) {
        setState(() {
          _loggedin = value;
        });
      }
    });
  }

  // Merging of room numbers is handled in `lib/requests.dart` where the
  // freshly fetched timetable is parsed and persisted. The UI should not
  // perform merging to avoid duplicating logic or persisting different
  // results. This placeholder remains to document intent.

  @override
  void dispose() {
    _timer?.cancel();
    _timer?.cancel();
    _highlightTimer?.cancel();
    _resub?.cancel();
    _debugSub?.cancel();
    _updateSub?.cancel();
    _loggedinSub?.cancel();
    _notificationResub?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _updateTimeRemaining();
        });
      }
    });
  }

  void _updateTimeRemaining() {
    if (_timetable == null) return;

    final dbg = GetIt.I<DebugService>();
    final now = dbg.enabled ? dbg.now : DateTime.now();
    final currentWeekday = now.weekday; // 1 = Monday, 7 = Sunday
    final weekdayNames = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];

    // Find today's lessons
    final todayLessons = _timetable!.days.where((day) {
      final dayName = day.day.toLowerCase();
      return dayName.contains(weekdayNames[currentWeekday - 1]);
    }).toList();

    if (todayLessons.isEmpty || todayLessons.first.lessons.isEmpty) {
      _timeRemaining = '';
      _nextLessonId = null;
      return;
    }

    // Find the next lesson today
    for (final lesson in todayLessons.first.lessons) {
      try {
        final startTime = _parseTimeString(lesson.startTime);
        if (startTime != null) {
          final lessonTime = DateTime(
            now.year,
            now.month,
            now.day,
            startTime.hour,
            startTime.minute,
          );

          final difference = lessonTime.difference(now);
          if (difference > Duration.zero) {
            final hours = difference.inHours;
            final minutes = difference.inMinutes.remainder(60);
            _timeRemaining =
                ' (in ${hours > 0 ? '${hours}h ' : ''}${minutes}m)';
            _nextLessonId =
                '${lesson.name}-${lesson.startTime}'; // Create a unique ID for the next lesson
            return;
          }
        }
      } catch (e) {
        debugPrint('Error calculating time remaining: $e');
      }
    }

    _timeRemaining = '';
    _nextLessonId = null;
  }

  TimeOfDay? _parseTimeString(String timeString) {
    try {
      // Handle formats like "9:45AM" or "9:45 AM"
      final cleanTime = timeString.trim().toUpperCase();
      final isPM = cleanTime.contains('PM');

      // Extract just the numbers
      final timePart = cleanTime.replaceAll(RegExp(r'[^0-9:]'), '');
      final parts = timePart.split(':');

      if (parts.length >= 2) {
        var hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);

        // Convert to 24-hour format if needed
        if (isPM && hour < 12) {
          hour += 12;
        } else if (!isPM && hour == 12) {
          hour = 0; // 12 AM is 0:00 in 24-hour format
        }

        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (e) {
      debugPrint('Error parsing time "$timeString": $e');
    }
    return null;
  }

  Widget _buildEmptyStateTimetable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_month,
              size: 120,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'No Timetable Available',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Sign in to fetch your timetable. If you are not logged in, you will be prompted to log in first.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () async {
                await _reloadTimetable();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Fetch Timetable'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // Helper function to deeply convert Map<dynamic, dynamic> to Map<String, dynamic>
  Map<String, dynamic> _convertToTypedMap(Map<dynamic, dynamic> map) {
    return Map<String, dynamic>.fromIterable(
      map.entries,
      key: (entry) => entry.key.toString(),
      value: (entry) {
        if (entry.value is Map<dynamic, dynamic>) {
          return _convertToTypedMap(entry.value);
        } else if (entry.value is List) {
          return (entry.value as List).map((item) {
            if (item is Map<dynamic, dynamic>) {
              return _convertToTypedMap(item);
            }
            return item;
          }).toList();
        }
        return entry.value;
      },
    );
  }

  Future<void> init() async {
    final debugMode = await settings.getBool('debugMode');
    setState(() {
      _debugMode = debugMode;
    });
    // Initialize global debug service state (if available)
    try {
      final dbg = GetIt.I<DebugService>();
      dbg.setEnabled(_debugMode);
    } catch (_) {}
    final timetableData = await settings.getMap('timetable');
    final timetableUpdated = await settings.getKey('timetableUpdated');
    final loggedin = await settings.getBool('loggedin');
    _requests.updateApp();
    if (timetableData.isNotEmpty) {
      try {
        // Convert the map and all nested maps to ensure they have the correct type
        final typedData = _convertToTypedMap(timetableData);
        final timetable = models.Timetable.fromJson(typedData);
        if (mounted) {
          setState(() {
            _timetable = timetable;
            _timetableUpdated = timetableUpdated;
            _error = '';
            _loggedin = loggedin;
            _isLoading = false;
          });
          _scheduleNotifications();
          if (!_debugMode) {
            _loadTimetable();
          }
        }
      } catch (e, stacktrace) {
        debugPrint('Error loading timetable: $e');
        debugPrint('Stacktrace: $stacktrace');
        await settings.setMap('timetable', {});
      }
    } else {
      if (!_debugMode) {
        _loadTimetable();
      }
    }
  }

  Future<void> _loadTimetable() async {
    if (!mounted) return;
    if (_error.isNotEmpty) {
      setState(() {
        _error = '';
      });
    }

    try {
      final timetable = await _requests.getTimeTable();
      final timetableUpdated = await settings.getKey('timetableUpdated');
      final loggedin = await settings.getBool('loggedin');

      if (timetable != null) {
        try {
          // The requests layer now performs any necessary merging and
          // persistence. The UI should simply consume the timetable returned
          // by `getTimeTable()` and update state accordingly.
          if (mounted) {
            setState(() {
              _timetable = timetable;
              _timetableUpdated = timetableUpdated;
              _loggedin = loggedin;
              _isLoading = false;
              _error = '';
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _timetable = timetable;
              _timetableUpdated = timetableUpdated;
              _loggedin = loggedin;
            });
          }
        }

        _scheduleNotifications();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load timetable: ${e.toString()}';
          _isLoading = true;
        });
      }
    }
  }

  Future<void> _reloadTimetable() async {
    if (_loggedin) {
      await _loadTimetable();
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Login Required'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400, // Fixed height to prevent infinite constraints
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri('https://my.nulc.ac.uk'),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                databaseEnabled: true,
                useOnLoadResource: true,
                allowsBackForwardNavigationGestures: true,
                thirdPartyCookiesEnabled: true,
                allowsInlineMediaPlayback: true,
                mediaPlaybackRequiresUserGesture: false,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                cacheEnabled: true,
                clearCache: false,
                useShouldOverrideUrlLoading: false,
              ),
              onReceivedServerTrustAuthRequest: (controller, challenge) async {
                // Allow SSL certificate for my.nulc.ac.uk
                if (challenge.protectionSpace.host == 'my.nulc.ac.uk') {
                  return ServerTrustAuthResponse(
                    action: ServerTrustAuthResponseAction.PROCEED,
                  );
                }
                return ServerTrustAuthResponse(
                  action: ServerTrustAuthResponseAction.CANCEL,
                );
              },
              onLoadStop: (controller, url) async {
                if (!url.toString().contains('authToken') &&
                    url.toString().startsWith('https://my.nulc.ac.uk')) {
                  try {
                    if (ctx.mounted) {
                      // Close any open dialogs first
                      if (Navigator.canPop(ctx)) {
                        Navigator.of(ctx).popUntil((route) => route.isFirst);
                      }
                      // Show error dialog
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Cannot Login'),
                          content: const Text(
                            'This error is commonly caused by being connected to college wifi which prevents this page from redirecting to the login screen.\n\nPlease try again using mobile data or a different network.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                              },
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    }
                  } catch (e) {
                    debugPrint('Error showing login error dialog: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Unable to authenticate. Please check your connection.',
                          ),
                          duration: Duration(seconds: 5),
                        ),
                      );
                    }
                  }
                  return; // Stop further execution on auth error
                }

                if (url.toString().startsWith('https://my.nulc.ac.uk')) {
                  try {
                    // Extract identity from URL authToken if present
                    await _requests.processAuthUrl(url.toString());

                    // Save cookies first
                    final cookies = await _cookieManager.getCookies(
                      url: WebUri('https://my.nulc.ac.uk'),
                    );
                    await settings.setKey('cookies', cookies.toString());
                    await settings.setBool('loggedin', true);
                    // Notify other listeners that login state changed
                    try {
                      _requests.loggedinController.add(true);
                    } catch (_) {}

                    // Fetch user profile identity (independent of timetable)
                    await _requests.fetchUserProfile();

                    // Clean up after navigation is scheduled
                    await _cookieManager.deleteAllCookies();

                    _loadTimetable();

                    if (ctx.mounted) {
                      Navigator.of(ctx).pop(); // Close the login dialog
                    }
                  } catch (e) {
                    debugPrint('Login error: $e');
                    if (ctx.mounted) {
                      // ignore: use_build_context_synchronously
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Error during login. Please try again.',
                          ),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  }
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      return DateFormat('MMM d, yyyy hh:mm a').format(dateTime.toLocal());
    } catch (e) {
      return timestamp; // Return original string if parsing fails
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Timetable'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _reloadTimetable,
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _timetable == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadTimetable,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_timetable == null) {
      return _buildEmptyStateTimetable();
    }

    if (_timetable!.days.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          await _reloadTimetable();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height - 200,
            child: _buildEmptyStateTimetable(),
          ),
        ),
      );
    }

    // Find the index of the current day or the next available day
    final dbg = GetIt.I<DebugService>();
    final now = dbg.enabled ? dbg.now : DateTime.now();
    final currentWeekday = now.weekday;
    final weekdayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    int initialIndex = 0;
    bool found = false;

    // If we have an initialDay from deep link, use that
    if (widget.initialDay != null) {
      for (int j = 0; j < _timetable!.days.length; j++) {
        if (_timetable!.days[j].day.toLowerCase().contains(
          widget.initialDay!.toLowerCase(),
        )) {
          initialIndex = j;
          found = true;
          break;
        }
      }
    }

    // If no initial day specified or not found, try to find today or the next available day
    if (!found) {
      for (int i = 0; i < 7; i++) {
        final checkWeekday =
            (currentWeekday - 1 + i) % 7; // Start from today, go forward
        final dayName = weekdayNames[checkWeekday];

        // Find the first matching day in our timetable
        for (int j = 0; j < _timetable!.days.length; j++) {
          if (_timetable!.days[j].day.toLowerCase().contains(
            dayName.toLowerCase(),
          )) {
            initialIndex = j;
            found = true;
            break;
          }
        }

        if (found) break;

        // If we've checked all days of the week, just use the first day
        if (i == 6) {
          initialIndex = 0;
        }
      }
    }

    return DefaultTabController(
      initialIndex: initialIndex,
      length: _timetable!.days.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabs: _timetable!.days.map((day) => Tab(text: day.day)).toList(),
          ),
          if (_timetableUpdated.isNotEmpty)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainer,
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Last updated: ${_formatTimestamp(_timetableUpdated)}  ${_loggedin ? '(Logged in)' : '(Not logged in)'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(
                    context,
                  ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: TabBarView(
              children: _timetable!.days.map((day) {
                final dayIndex = _timetable!.days.indexOf(day);
                // Only show highlight on the initial day (or current day if using deep link)
                final isTargetDay = widget.initialDay != null
                    ? day.day.toLowerCase().contains(
                        widget.initialDay!.toLowerCase(),
                      )
                    : dayIndex == initialIndex;

                return RefreshIndicator(
                  onRefresh: () async {
                    await _reloadTimetable();
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: day.lessons.length,
                    itemBuilder: (context, index) {
                      final lesson = day.lessons[index];
                      final isHighlighted =
                          isTargetDay && _highlightLessonIndex == index;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: isHighlighted
                            ? BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              )
                            : null,
                        child: Card(
                          margin: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 8,
                          ),
                          color: isHighlighted
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          child: ListTile(
                            title: Text(
                              lesson.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isHighlighted
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer
                                    : null,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${lesson.startTime} - ${lesson.endTime}${_nextLessonId == '${lesson.name}-${lesson.startTime}' ? _timeRemaining : ''}',
                                  style: isHighlighted
                                      ? TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer,
                                        )
                                      : null,
                                ),
                                Text(
                                  'Room: ${lesson.room}',
                                  style: isHighlighted
                                      ? TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer,
                                        )
                                      : null,
                                ),
                                Text(
                                  'Teachers: ${lesson.teachers.join(", ")}',
                                  style: isHighlighted
                                      ? TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer,
                                        )
                                      : null,
                                ),
                                Text(
                                  'Course: ${lesson.course} (${lesson.group})',
                                  style: isHighlighted
                                      ? TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                            isThreeLine: true,
                            onTap: kInsertRoomNumbers
                                ? () {
                                    _editRoom(dayIndex, index);
                                  }
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _scheduleNotifications() async {
    try {
      final notificationsEnabled = await settings.getNotificationsEnabled();
      if (!notificationsEnabled) {
        await _notificationService.cancelAllNotifications();
        return;
      }

      await _notificationService.cancelAllNotifications();

      if (_timetable == null) return;

      final notifyOnStart = await settings.getNotifyOnStartTime();
      final beforeEnabled = await settings.getNotifyMinutesBeforeEnabled();
      final minutesBefore = await settings.getNotifyMinutesBefore();

      final dbg = GetIt.I<DebugService>();
      final now = dbg.enabled ? dbg.now : DateTime.now();
      int notificationId = 0;

      String examKey(Exam exam) {
        return '${exam.date}|${exam.startTime}|${exam.finishTime}|${exam.subjectDescription}|${exam.examRoom}|${exam.seatNumber}';
      }

      final weekdayMap = {
        'monday': DateTime.monday,
        'tuesday': DateTime.tuesday,
        'wednesday': DateTime.wednesday,
        'thursday': DateTime.thursday,
        'friday': DateTime.friday,
        'saturday': DateTime.saturday,
        'sunday': DateTime.sunday,
      };

      for (final day in _timetable!.days) {
        final dayName = day.day.toLowerCase().split(' ').first;
        final targetWeekday = weekdayMap[dayName];
        if (targetWeekday == null) continue;

        for (final lesson in day.lessons) {
          final startTime = _parseTimeString(lesson.startTime);
          if (startTime != null) {
            var lessonDate = DateTime(now.year, now.month, now.day);
            while (lessonDate.weekday != targetWeekday) {
              lessonDate = lessonDate.add(const Duration(days: 1));
            }

            var lessonDateTime = DateTime(
              lessonDate.year,
              lessonDate.month,
              lessonDate.day,
              startTime.hour,
              startTime.minute,
            );

            if (lessonDateTime.isBefore(now)) {
              lessonDateTime = lessonDateTime.add(const Duration(days: 7));
            }

            if (notifyOnStart) {
              await _notificationService.scheduleNotification(
                notificationId++,
                lesson.name,
                'Starts now in room ${lesson.room}',
                lessonDateTime,
                repeatWeekly: true,
                type: NotificationType.lessonStart,
              );
            }

            if (beforeEnabled && minutesBefore > 0) {
              final beforeTime = lessonDateTime.subtract(
                Duration(minutes: minutesBefore),
              );
              if (beforeTime.isAfter(now)) {
                await _notificationService.scheduleNotification(
                  notificationId++,
                  lesson.name,
                  'Starts in $minutesBefore minutes in room ${lesson.room}',
                  beforeTime,
                  repeatWeekly: true,
                  type: NotificationType.minutesBefore,
                );
              }
            }
          }
        }
      }

      // Exams: one-off notifications (not weekly).
      try {
        final examTimetableData = await settings.getMap('examTimetable');
        if (examTimetableData.isNotEmpty) {
          final typedExamData = _convertToTypedMap(examTimetableData);
          final examTimetable = ExamTimetable.fromJson(typedExamData);

          for (final exam in examTimetable.exams) {
            // Parse exam date: typically dd-MM-yyyy.
            final dateParts = exam.date.split(RegExp(r'[-/]'));
            if (dateParts.length != 3) continue;
            final day = int.tryParse(dateParts[0]);
            final month = int.tryParse(dateParts[1]);
            final year = int.tryParse(dateParts[2]);
            if (day == null || month == null || year == null) continue;

            final startParts = exam.startTime.split(':');
            if (startParts.length != 2) continue;
            final sh = int.tryParse(startParts[0]);
            final sm = int.tryParse(startParts[1]);
            if (sh == null || sm == null) continue;

            final startDateTime = DateTime(year, month, day, sh, sm);
            if (!startDateTime.isAfter(now)) continue;

            final payload = 'exam:${examKey(exam)}';

            if (notifyOnStart) {
              await _notificationService.scheduleNotification(
                notificationId++,
                exam.subjectDescription,
                'Starts now in ${exam.examRoom} (Seat ${exam.seatNumber})',
                startDateTime,
                type: NotificationType.examStart,
                payload: payload,
              );
            }

            // Exam notifications always go off 45 minutes before
            if (beforeEnabled) {
              final beforeTime = startDateTime.subtract(
                const Duration(minutes: 45),
              );
              if (beforeTime.isAfter(now)) {
                // Determine notification body based on preroom availability
                final body =
                    exam.preRoom.isNotEmpty &&
                        exam.preRoom.split(' ').length < 6
                    ? 'Go to preroom ${exam.preRoom} in 45 minutes (Seat ${exam.seatNumber})'
                    : 'Starts in 45 minutes in ${exam.examRoom} (Seat ${exam.seatNumber})';

                await _notificationService.scheduleNotification(
                  notificationId++,
                  exam.subjectDescription,
                  body,
                  beforeTime,
                  type: NotificationType.examMinutesBefore,
                  payload: payload,
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error scheduling exam notifications: $e');
      }
    } catch (e) {
      debugPrint('Error scheduling notifications: $e');
    }
  }

  Future<void> _editRoom(int dayIndex, int lessonIndex) async {
    if (_timetable == null) return;

    final lesson = _timetable!.days[dayIndex].lessons[lessonIndex];
    final controller = TextEditingController(text: lesson.room);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Room'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Room'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newRoom = controller.text.trim();
              setState(() {
                _timetable = models.Timetable(
                  days: List.generate(_timetable!.days.length, (dIdx) {
                    final d = _timetable!.days[dIdx];
                    if (dIdx != dayIndex) return d;
                    final newLessons = List<models.Lesson>.from(d.lessons);
                    final old = newLessons[lessonIndex];
                    newLessons[lessonIndex] = models.Lesson(
                      teachers: old.teachers,
                      course: old.course,
                      group: old.group,
                      name: old.name,
                      startTime: old.startTime,
                      endTime: old.endTime,
                      room: newRoom,
                    );
                    return models.DaySchedule(day: d.day, lessons: newLessons);
                  }),
                );
              });

              // Persist changes
              await settings.setMap('timetable', _timetable!.toJson());
              await _scheduleNotifications();
              // ignore: use_build_context_synchronously
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
