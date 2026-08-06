import 'dart:async';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nscgschedule/widget_service.dart';
import 'package:nscgschedule/models/timetable_models.dart';
import 'package:nscgschedule/models/exam_models.dart';
import 'package:nscgschedule/settings.dart';
import 'package:nscgschedule/notifications.dart';
import 'package:nscgschedule/watch_service.dart';
import 'package:nscgschedule/services/timetable_sync_service.dart';

class DebugService {
  static final DebugService instance = DebugService._internal();

  DebugService._internal();

  final ValueStreamController<bool> _enabledController =
      ValueStreamController<bool>(false);
  final ValueStreamController<DateTime> _nowController =
      ValueStreamController<DateTime>(DateTime.now());

  Timer? _ticker;
  final Settings _settings = Settings();
  final Random _random = Random();

  static const List<String> _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
  ];

  static const List<Map<String, dynamic>> _subjectTemplates = [
    {
      'name': 'Computer Science: Programming',
      'course': 'CS-301',
      'group': 'A1',
      'teachers': ['Dr. A. Smith'],
      'room': 'IT-101',
    },
    {
      'name': 'Software Development & Architecture',
      'course': 'SWE-201',
      'group': 'B2',
      'teachers': ['Prof. R. Davies'],
      'room': 'IT-104',
    },
    {
      'name': 'Database Design & SQL Systems',
      'course': 'DB-105',
      'group': 'A2',
      'teachers': ['Ms. E. Taylor'],
      'room': 'Lab-3',
    },
    {
      'name': 'Cyber Security & Network Defense',
      'course': 'SEC-210',
      'group': 'C1',
      'teachers': ['Mr. J. Wilson'],
      'room': 'Lab-7',
    },
    {
      'name': 'Mathematics for Computing',
      'course': 'MTH-110',
      'group': 'A1',
      'teachers': ['Dr. S. Patel', 'Ms. H. Clark'],
      'room': 'B204',
    },
    {
      'name': 'Web Applications & UI/UX',
      'course': 'WEB-304',
      'group': 'B1',
      'teachers': ['Mr. M. Evans'],
      'room': 'C112',
    },
    {
      'name': 'Algorithms & Data Structures',
      'course': 'CS-202',
      'group': 'A2',
      'teachers': ['Dr. A. Smith'],
      'room': 'IT-102',
    },
    {
      'name': 'Cloud Computing & DevOps',
      'course': 'CLD-305',
      'group': 'C2',
      'teachers': ['Prof. R. Davies'],
      'room': 'IT-105',
    },
    {
      'name': 'Artificial Intelligence & Data Science',
      'course': 'AI-401',
      'group': 'A1',
      'teachers': ['Dr. S. Patel'],
      'room': 'Sci-Lab',
    },
  ];

  static const List<List<String>> _timeSlots = [
    ['9:00 AM', '10:30 AM'],
    ['10:45 AM', '12:15 PM'],
    ['1:00 PM', '2:30 PM'],
    ['2:45 PM', '4:15 PM'],
  ];

  static const List<Map<String, String>> _examTemplates = [
    {
      'subject': 'Paper 1: Computer Systems & Architecture',
      'board': 'EDEXCEL',
      'paper': '8CS0/01',
      'startTime': '09:00',
      'finishTime': '11:00',
      'room': 'Sports Hall',
      'seat': 'A-12',
    },
    {
      'subject': 'Paper 2: Algorithms, Programming & Logic',
      'board': 'EDEXCEL',
      'paper': '8CS0/02',
      'startTime': '13:30',
      'finishTime': '15:30',
      'room': 'Sports Hall',
      'seat': 'A-12',
    },
    {
      'subject': 'Unit 1: Fundamentals of IT & Cyber Security',
      'board': 'OCR',
      'paper': 'IT-U1',
      'startTime': '09:00',
      'finishTime': '10:30',
      'room': 'IT Lab 2',
      'seat': 'B-05',
    },
    {
      'subject': 'Pure Mathematics & Statistical Modeling',
      'board': 'AQA',
      'paper': '7357/1',
      'startTime': '09:00',
      'finishTime': '11:00',
      'room': 'Main Hall',
      'seat': 'C-18',
    },
    {
      'subject': 'Software Engineering & Database Systems',
      'board': 'OCR',
      'paper': 'SWE-301',
      'startTime': '13:30',
      'finishTime': '15:00',
      'room': 'Main Hall',
      'seat': 'C-18',
    },
  ];

  // Expose simple getters
  bool get enabled => _enabledController.value;
  DateTime get now => _nowController.value;

  // ValueListenable-like access
  ValueStreamController<bool> get enabledController => _enabledController;
  ValueStreamController<DateTime> get nowController => _nowController;

  void setEnabled(bool v) {
    _enabledController.value = v;
    if (v) {
      _startTicker();
    } else {
      _stopTicker();
    }
    _saveToPrefs();
    _refreshWidgets();
  }

  void setNow(DateTime dt) {
    _nowController.value = dt;
    _saveToPrefs();
    _refreshWidgets();
  }

  void advance(Duration d) {
    _nowController.value = _nowController.value.add(d);
    _saveToPrefs();
    _refreshWidgets();
  }

  void _startTicker() {
    _stopTicker();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      _nowController.value = _nowController.value.add(
        const Duration(seconds: 1),
      );
      // Update widgets every minute
      if (_nowController.value.second == 0) {
        _refreshWidgets();
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Save debug state to SharedPreferences for widgets to access
  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('debug_enabled', _enabledController.value);
    await prefs.setInt(
      'debug_time_millis',
      _nowController.value.millisecondsSinceEpoch,
    );
    // Store the real time when debug time was set so widgets can calculate elapsed time
    await prefs.setInt(
      'debug_set_real_time',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Refresh widgets to reflect debug time changes
  void _refreshWidgets() {
    WidgetService.instance.updateAllWidgets();
  }

  /// Load debug state from SharedPreferences
  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('debug_enabled') ?? false;
      final timeMillis = prefs.getInt('debug_time_millis');

      _enabledController.value = enabled;
      if (timeMillis != null) {
        _nowController.value = DateTime.fromMillisecondsSinceEpoch(timeMillis);
      }

      if (enabled) {
        _startTicker();
      }
    } catch (e) {
      // Ignore errors
    }
  }

  /// Generate and persist a randomized weekly timetable
  Future<Timetable> generateRandomTimetable() async {
    final List<DaySchedule> days = [];
    final shuffledSubjects = List<Map<String, dynamic>>.from(_subjectTemplates)
      ..shuffle(_random);

    var subjectIndex = 0;

    for (final dayName in _days) {
      // Pick 2 to 3 lessons per day
      final lessonCount = 2 + _random.nextInt(2);
      final slotIndices = <int>{};
      while (slotIndices.length < lessonCount) {
        slotIndices.add(_random.nextInt(_timeSlots.length));
      }
      final sortedSlots = slotIndices.toList()..sort();

      final List<Lesson> dayLessons = [];
      for (final slotIdx in sortedSlots) {
        final tpl = shuffledSubjects[subjectIndex % shuffledSubjects.length];
        subjectIndex++;

        final slot = _timeSlots[slotIdx];
        dayLessons.add(
          Lesson(
            teachers: List<String>.from(tpl['teachers'] as List),
            course: tpl['course'] as String,
            group: tpl['group'] as String,
            name: tpl['name'] as String,
            startTime: slot[0],
            endTime: slot[1],
            room: tpl['room'] as String,
          ),
        );
      }

      days.add(DaySchedule(day: dayName, lessons: dayLessons));
    }

    final timetable = Timetable(days: days);

    // Save to settings
    await _settings.setMap('timetable', timetable.toJson());
    await _settings.setKey('timetableUpdated', DateTime.now().toIso8601String());

    // Trigger syncs and notifications
    try {
      if (GetIt.I.isRegistered<NotificationService>()) {
        GetIt.I<NotificationService>().requestReschedule();
      }
    } catch (_) {}

    try {
      await WatchService.instance.syncTimetable();
      await WatchService.instance.updateContext();
    } catch (_) {}

    try {
      await WidgetService.instance.syncTimetableToWidget();
    } catch (_) {}

    try {
      if (GetIt.I.isRegistered<TimetableSyncService>()) {
        final syncService = GetIt.I<TimetableSyncService>();
        if (await syncService.isTimetablePublished()) {
          await syncService.updateOnlineTimetable(timetable: timetable);
        }
      }
    } catch (_) {}

    return timetable;
  }

  /// Generate and persist randomized mock exam timetable
  Future<ExamTimetable> generateRandomExamTimetable() async {
    final existingOwner = await _settings.getKey('timetableOwner');
    final existingRef = await _settings.getKey('timetableOwnerRef');
    final studentName =
        existingOwner.isNotEmpty ? existingOwner : 'Alex Morgan';
    final studentRef = existingRef.isNotEmpty ? existingRef : '849201';

    final now = DateTime.now();
    final List<Exam> exams = [];

    final examCount = 3 + _random.nextInt(3);
    final shuffledExams = List<Map<String, String>>.from(_examTemplates)
      ..shuffle(_random);

    final daysOffsets = [5, 9, 14, 21, 28];

    for (var i = 0; i < examCount && i < shuffledExams.length; i++) {
      final tpl = shuffledExams[i];
      final examDate = now.add(Duration(days: daysOffsets[i]));
      final dateStr = DateFormat('dd-MM-yyyy').format(examDate);

      exams.add(
        Exam(
          date: dateStr,
          boardCode: tpl['board']!,
          paper: tpl['paper']!,
          startTime: tpl['startTime']!,
          finishTime: tpl['finishTime']!,
          subjectDescription: tpl['subject']!,
          preRoom: '',
          examRoom: tpl['room']!,
          seatNumber: tpl['seat']!,
          additional: '',
        ),
      );
    }

    final examTimetable = ExamTimetable(
      hasExams: true,
      studentInfo: StudentInfo(
        refNo: studentRef,
        name: studentName,
        dateOfBirth: '14/08/2007',
        uln: '9876543210',
        candidateNo: '4129',
      ),
      exams: exams,
      warningMessage:
          'Please arrive at least 15 minutes before the exam start time. No smart devices or unauthorized notes allowed in exam rooms.',
    );

    // Save to settings
    await _settings.setMap('examTimetable', examTimetable.toJson());
    await _settings.setKey(
      'examTimetableUpdated',
      DateTime.now().toIso8601String(),
    );

    // Trigger watch & widget syncs
    try {
      await WatchService.instance.syncExamTimetable();
      await WatchService.instance.updateContext();
    } catch (_) {}

    try {
      await WidgetService.instance.syncExamTimetableToWidget();
    } catch (_) {}

    return examTimetable;
  }

  /// Clear mock timetable and exams
  Future<void> clearMockData() async {
    await _settings.setMap('timetable', {});
    await _settings.setKey('timetableUpdated', '');
    await _settings.setMap('examTimetable', {});
    await _settings.setKey('examTimetableUpdated', '');

    try {
      if (GetIt.I.isRegistered<NotificationService>()) {
        GetIt.I<NotificationService>().requestReschedule();
      }
    } catch (_) {}

    try {
      await WatchService.instance.syncTimetable();
      await WatchService.instance.syncExamTimetable();
      await WatchService.instance.updateContext();
    } catch (_) {}

    try {
      await WidgetService.instance.syncTimetableToWidget();
      await WidgetService.instance.syncExamTimetableToWidget();
    } catch (_) {}
  }

  void dispose() {
    _stopTicker();
  }
}

/// Minimal value holder that mirrors ValueNotifier but exposes `value`
class ValueStreamController<T> {
  T _value;
  final StreamController<T> _controller;
  ValueStreamController(this._value)
    : _controller = StreamController<T>.broadcast();

  T get value => _value;
  set value(T v) {
    _value = v;
    try {
      _controller.add(v);
    } catch (_) {}
  }

  Stream<T> get stream => _controller.stream;
  void dispose() => _controller.close();
}
