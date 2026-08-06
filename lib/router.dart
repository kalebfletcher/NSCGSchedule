import 'package:flutter/material.dart';
import 'package:nscgschedule/main.dart';
import 'package:nscgschedule/login.dart';
import 'package:nscgschedule/settings_page.dart';
import 'package:nscgschedule/timetable.dart';
import 'package:nscgschedule/exam_timetable.dart';
import 'package:nscgschedule/exam_details.dart';
import 'package:nscgschedule/friends_list.dart';
import 'package:nscgschedule/friends_qr.dart';
import 'package:nscgschedule/friends_gaps.dart';
import 'package:nscgschedule/friend_profile.dart';
import 'package:nscgschedule/timetable_access_list.dart';
import 'package:nscgschedule/friends_onboarding.dart';
import 'package:nscgschedule/privacy_policy_screen.dart';
import 'package:nscgschedule/updater.dart';
import 'package:go_router/go_router.dart';
import 'package:nscgschedule/settings.dart';
import 'package:nscgschedule/requests.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:nscgschedule/models/timetable_models.dart' as models;
import 'package:nscgschedule/models/exam_models.dart' as exammodels;
import 'package:nscgschedule/debug_service.dart';
import 'package:get_it/get_it.dart';

final GoRouter routerController = GoRouter(
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        return LoadingScreen();
      },
    ),
    GoRoute(
      path: '/login',
      builder: (BuildContext context, GoRouterState state) {
        return Login();
      },
    ),
    ShellRoute(
      builder: (BuildContext context, GoRouterState state, Widget child) {
        return MainShell(child: child);
      },
      routes: <RouteBase>[
        GoRoute(
          path: '/Timetable',
          builder: (BuildContext context, GoRouterState state) {
            final day = state.uri.queryParameters['day'];
            final lessonStr = state.uri.queryParameters['lesson'];
            final lessonIndex = lessonStr != null
                ? int.tryParse(lessonStr)
                : null;
            return TimetableScreen(
              initialDay: day,
              highlightLessonIndex: lessonIndex,
            );
          },
        ),
        GoRoute(
          path: '/exams',
          builder: (BuildContext context, GoRouterState state) {
            final open = state.uri.queryParameters['open'];
            return ExamTimetableScreen(initialExamKey: open);
          },
          routes: <RouteBase>[
            GoRoute(
              path: 'details',
              builder: (BuildContext context, GoRouterState state) {
                return ExamDetailsScreen();
              },
            ),
          ],
        ),
        GoRoute(
          path: '/friends',
          builder: (BuildContext context, GoRouterState state) {
            return FriendsListScreen();
          },
          routes: <RouteBase>[
            GoRoute(
              path: 'share',
              builder: (BuildContext context, GoRouterState state) {
                return ShareQRScreen();
              },
            ),
            GoRoute(
              path: 'scan',
              builder: (BuildContext context, GoRouterState state) {
                return ScanQRScreen();
              },
            ),
            GoRoute(
              path: 'gaps/:friendId',
              builder: (BuildContext context, GoRouterState state) {
                final friendId = state.pathParameters['friendId']!;
                return GapsFinderScreen(friendId: friendId);
              },
            ),
            GoRoute(
              path: 'profile/:friendId',
              builder: (BuildContext context, GoRouterState state) {
                final friendId = state.pathParameters['friendId']!;
                return FriendProfileScreen(friendId: friendId);
              },
            ),
            GoRoute(
              path: 'sync-access',
              builder: (BuildContext context, GoRouterState state) {
                return TimetableAccessListScreen();
              },
            ),
            GoRoute(
              path: 'onboarding',
              builder: (BuildContext context, GoRouterState state) {
                return const FriendsOnboardingScreen();
              },
            ),
            GoRoute(
              path: 'privacy-policy',
              builder: (BuildContext context, GoRouterState state) {
                return const PrivacyPolicyScreen();
              },
            ),
          ],
        ),
        GoRoute(
          path: '/settings',
          builder: (BuildContext context, GoRouterState state) {
            return SettingsPage();
          },
          routes: <RouteBase>[
            GoRoute(
              path: 'updates',
              builder: (BuildContext context, GoRouterState state) {
                return UpdaterScreen();
              },
            ),
            GoRoute(
              path: 'privacy-policy',
              builder: (BuildContext context, GoRouterState state) {
                return const PrivacyPolicyScreen(isReviewOnly: true);
              },
            ),
          ],
        ),
      ],
    ),
  ],
  redirect: (BuildContext context, GoRouterState state) async {
    final timetable = await settings.getMap('timetable');
    final isAuthenticated = timetable.toString() != '{}';
    final currentPath = state.uri.path;

    switch (currentPath) {
      case '/':
        if (!isAuthenticated) return '/login';
        if (isAuthenticated) return '/Timetable';
        break;

      case '/login':
        if (isAuthenticated) return '/Timetable';
        return null;

      default:
        if (isAuthenticated) return null;
        return '/';
    }
    return null;
  },
);

class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const List<String> _paths = [
    '/Timetable',
    '/exams',
    '/friends',
    '/settings',
  ];

  Timer? _miniTimer;
  Map<String, dynamic>?
  _activeItem; // {'type':'exam'|'lesson', 'title':..., 'time':DateTime, ...}
  bool _autoNavigatedToExams = false;
  bool _debugMode = false;
  DateTime _debugNow = DateTime.now();
  StreamSubscription<bool>? _debugSub;
  StreamSubscription<bool>? _updateSub;
  bool _hasUpdate = false;
  final NSCGRequests _requests = NSCGRequests.instance;

  int _locationToIndex(String loc) {
    if (loc.startsWith('/Timetable')) return 0;
    if (loc.startsWith('/exams')) return 1;
    if (loc.startsWith('/friends')) return 2;
    if (loc.startsWith('/settings')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final loc = GoRouter.of(context).state.uri.path;
    final currentIndex = _locationToIndex(loc);

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_debugMode) _buildDebugControls(),
          if (_activeItem != null) _buildMiniPlayer(context),
          NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: (index) {
              final target = _paths[index];
              if (target != loc) {
                context.go(target);
              }
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.calendar_today),
                label: 'Timetable',
              ),
              const NavigationDestination(
                icon: Icon(Icons.school),
                label: 'Exams',
              ),
              const NavigationDestination(
                icon: Icon(Icons.people),
                label: 'Friends',
              ),
              NavigationDestination(
                icon: _hasUpdate
                    ? const Icon(Icons.settings_suggest)
                    : const Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDebugControls() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.bug_report),
          const SizedBox(width: 8),
          Text(
            'Debug time: ${DateFormat('HH:mm').format(GetIt.I<DebugService>().now)}',
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              setState(() {
                _debugNow = _debugNow.subtract(const Duration(minutes: 15));
                // update global debug time
                try {
                  GetIt.I<DebugService>().setNow(_debugNow);
                  GetIt.I<DebugService>().setEnabled(true);
                } catch (_) {}
                _updateMiniPlayer();
              });
            },
            child: const Text('-15m'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _debugNow = _debugNow.add(const Duration(minutes: 15));
                try {
                  GetIt.I<DebugService>().setNow(_debugNow);
                  GetIt.I<DebugService>().setEnabled(true);
                } catch (_) {}
                _updateMiniPlayer();
              });
            },
            child: const Text('+15m'),
          ),
          TextButton(
            onPressed: () async {
              // Allow the user to pick a specific date and time
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: _debugNow,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (pickedDate == null) return;
              final pickedTime = await showTimePicker(
                // ignore: use_build_context_synchronously
                context: context,
                initialTime: TimeOfDay.fromDateTime(_debugNow),
              );
              if (pickedTime == null) return;
              final combined = DateTime(
                pickedDate.year,
                pickedDate.month,
                pickedDate.day,
                pickedTime.hour,
                pickedTime.minute,
              );
              setState(() {
                _debugNow = combined;
                try {
                  GetIt.I<DebugService>().setNow(_debugNow);
                  GetIt.I<DebugService>().setEnabled(true);
                } catch (_) {}
                _updateMiniPlayer();
              });
            },
            child: const Text('Pick time'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _updateMiniPlayer();
    _miniTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateMiniPlayer();
    });
    _debugSub = _requests.debugModeController.stream.listen((value) {
      if (mounted) {
        setState(() {
          _debugMode = value;
        });
        // Sync to global DebugService
        try {
          final dbg = GetIt.I<DebugService>();
          dbg.setEnabled(value);
          dbg.setNow(_debugNow);
        } catch (_) {}
        _updateMiniPlayer();
      }
    });
    // initialize debug mode from settings so the debug controls show correctly
    () async {
      try {
        final saved = await settings.getBool('debugMode');
        if (mounted) {
          setState(() {
            _debugMode = saved;
          });
        }
        if (saved) {
          try {
            final dbg = GetIt.I<DebugService>();
            _debugNow = dbg.now;
            dbg.setEnabled(true);
          } catch (_) {}
        }
      } catch (_) {}
    }();
    // Subscribe to update notifications and trigger an initial check
    _updateSub = _requests.updateController.stream.listen((available) {
      if (mounted) {
        setState(() {
          _hasUpdate = available;
        });
      }
    });
    // Trigger a check (this will also update the controller)
    () async {
      try {
        await _requests.updateApp();
      } catch (_) {}
    }();
  }

  @override
  void dispose() {
    _miniTimer?.cancel();
    _debugSub?.cancel();
    _updateSub?.cancel();
    super.dispose();
  }

  Future<void> _updateMiniPlayer() async {
    try {
      final timetableData = await settings.getMap('timetable');
      final examData = await settings.getMap('examTimetable');

      models.Timetable? tt;
      exammodels.ExamTimetable? et;

      if (timetableData.isNotEmpty) {
        try {
          final typed = _convertToTypedMap(timetableData);
          tt = models.Timetable.fromJson(typed);
        } catch (_) {
          tt = null;
        }
      }

      if (examData.isNotEmpty) {
        try {
          final typed = _convertToTypedMap(examData);
          et = exammodels.ExamTimetable.fromJson(typed);
        } catch (_) {
          et = null;
        }
      }

      final dbg = GetIt.I<DebugService>();
      final now = dbg.enabled ? dbg.now : DateTime.now();

      // Check exams first (priority). Find any exam happening now or within 15 minutes.
      Map<String, dynamic>? selected;
      if (et != null && et.hasExams) {
        for (final ex in et.exams) {
          final date = ex.parsedDate;
          if (date == null) continue;
          final start = _parseExamDateTime(date, ex.startTime);
          final finish = _parseExamDateTime(date, ex.finishTime);
          if (start == null || finish == null) continue;
          if ((now.isAfter(start) && now.isBefore(finish)) ||
              (start.isAfter(now.subtract(const Duration(minutes: 1))) &&
                  start.difference(now) <= const Duration(hours: 2))) {
            selected = {
              'type': 'exam',
              'exam': ex,
              'start': start,
              'finish': finish,
            };
            break;
          }
        }
      }

      // If an exam has been detected within the next 2 hours, navigate there once.
      if (selected != null &&
          selected['type'] == 'exam' &&
          !_autoNavigatedToExams) {
        _autoNavigatedToExams = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            final loc = GoRouter.of(context).state.uri.path;
            if (!loc.startsWith('/exams')) context.go('/exams');
          } catch (_) {}
        });
      }

      // If no exam, check lessons
      if (selected == null && tt != null) {
        final weekdayNames = [
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
          'Sunday',
        ];
        final todayName =
            weekdayNames[(GetIt.I<DebugService>().enabled
                        ? GetIt.I<DebugService>().now
                        : DateTime.now())
                    .weekday -
                1];
        final today = tt.days.firstWhere(
          (d) => d.day == todayName,
          orElse: () => models.DaySchedule(day: todayName, lessons: []),
        );
        for (final lesson in today.lessons) {
          final start = _parseLessonDateTime(lesson.startTime);
          final end = _parseLessonDateTime(lesson.endTime);
          if (start == null) continue;
          if ((now.isAfter(start) && end != null && now.isBefore(end)) ||
              (start.isAfter(now) && start.difference(now).inMinutes <= 15)) {
            selected = {
              'type': 'lesson',
              'lesson': lesson,
              'start': start,
              'end': end,
            };
            break;
          }
        }
      }

      setState(() {
        _activeItem = selected;
      });
    } catch (e) {
      // ignore errors silently
    }
  }

  Map<String, dynamic> _convertToTypedMap(Map<dynamic, dynamic> map) {
    return Map<String, dynamic>.fromIterable(
      map.entries,
      key: (entry) => entry.key.toString(),
      value: (entry) {
        final v = entry.value;
        if (v is Map) {
          return _convertToTypedMap(v);
        } else if (v is List) {
          return v.map((item) {
            if (item is Map) return _convertToTypedMap(item);
            return item;
          }).toList();
        }
        return v;
      },
    );
  }

  DateTime? _parseExamDateTime(DateTime date, String timeStr) {
    try {
      final parts = timeStr.split(RegExp(r'[:\s]'));
      if (parts.length >= 2) {
        var hour = int.tryParse(parts[0]) ?? 0;
        var minute = int.tryParse(parts[1]) ?? 0;
        // Handle AM/PM if present
        final isPM = timeStr.toUpperCase().contains('PM');
        if (isPM && hour < 12) hour += 12;
        if (!isPM && hour == 12 && timeStr.toUpperCase().contains('AM')) {
          hour = 0;
        }
        return DateTime(date.year, date.month, date.day, hour, minute);
      }
    } catch (_) {}
    return null;
  }

  DateTime? _parseLessonDateTime(String timeStr) {
    try {
      final dbg = GetIt.I<DebugService>();
      final now = dbg.enabled ? dbg.now : DateTime.now();
      final clean = timeStr.trim().toUpperCase();
      final isPM = clean.contains('PM');
      final timePart = clean.replaceAll(RegExp(r'[^0-9:]'), '');
      final parts = timePart.split(':');
      if (parts.length >= 2) {
        var hour = int.tryParse(parts[0]) ?? 0;
        final minute = int.tryParse(parts[1]) ?? 0;
        if (isPM && hour < 12) hour += 12;
        if (!isPM && hour == 12 && clean.contains('AM')) hour = 0;
        return DateTime(now.year, now.month, now.day, hour, minute);
      }
    } catch (_) {}
    return null;
  }

  Widget _buildMiniPlayer(BuildContext context) {
    if (_activeItem == null) return const SizedBox.shrink();
    final type = _activeItem!['type'] as String;
    if (type == 'exam') {
      final exam = _activeItem!['exam'] as exammodels.Exam;
      final start = _activeItem!['start'] as DateTime;
      final finish = _activeItem!['finish'] as DateTime;
      final dbg = GetIt.I<DebugService>();
      final now = dbg.enabled ? dbg.now : DateTime.now();
      final isNow = now.isAfter(start) && now.isBefore(finish);
      final label = isNow
          ? 'Exam now'
          : 'Exam in ${start.difference(now).inMinutes}m';
      final progress = _computeProgress(start, finish, now);
      return GestureDetector(
        onTap: () => context.go('/exams'),
        child: Material(
          elevation: 2,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainer.withValues(alpha: 0.4),
                ),
              ),
              Container(
                color: Theme.of(context).colorScheme.surfaceContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exam.subjectDescription,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          Text(
                            '$label — ${exam.examRoom}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      final lesson = _activeItem!['lesson'] as models.Lesson;
      final start = _activeItem!['start'] as DateTime;
      final end = _activeItem!['end'] as DateTime?;
      final dbg = GetIt.I<DebugService>();
      final now = dbg.enabled ? dbg.now : DateTime.now();
      final isNow = end != null && now.isAfter(start) && now.isBefore(end);
      final label = isNow ? 'Now' : 'In ${start.difference(now).inMinutes}m';
      final progress = _computeProgress(start, end, now);
      return GestureDetector(
        onTap: () => context.go('/Timetable'),
        child: Material(
          elevation: 2,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainer.withValues(alpha: 0.4),
                ),
              ),
              Container(
                color: Theme.of(context).colorScheme.surfaceContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lesson.name,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          Text(
                            '$label — ${lesson.room}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  double _computeProgress(DateTime start, DateTime? end, DateTime now) {
    if (end == null) return 0.0;
    if (now.isBefore(start)) return 0.0;
    if (now.isAfter(end)) return 1.0;
    final total = end.difference(start).inSeconds;
    if (total <= 0) return 0.0;
    final passed = now.difference(start).inSeconds;
    return (passed / total).clamp(0.0, 1.0);
  }
}
