import 'package:hive_ce/hive.dart';
import 'package:nscgschedule/models/timetable_models.dart' as models;
import 'package:nscgschedule/models/exam_models.dart' as exam_models;

part 'friend_models.g.dart';

/// Privacy level for sharing timetable data
@HiveType(typeId: 0)
enum PrivacyLevel {
  @HiveField(0)
  freeTimeOnly, // Only shows when user is free

  @HiveField(1)
  busyBlocks, // Shows class times but hides subject/room

  @HiveField(2)
  fullDetails, // Shares everything
}

/// Represents a friend's timetable data
@HiveType(typeId: 1)
class Friend {
  @HiveField(0)
  final String id; // Unique identifier

  @HiveField(1)
  final String name;

  @HiveField(2)
  final PrivacyLevel privacyLevel;

  @HiveField(3)
  final FriendTimetable timetable;

  @HiveField(4)
  final DateTime addedAt;

  @HiveField(5)
  final String? profilePicPath; // Optional local profile picture path (not shared)
  @HiveField(6)
  final String? userId; // Optional stable user identifier (e.g. C123456)
  @HiveField(7)
  final bool isOnlineSync;
  @HiveField(8)
  final String? syncFileId;
  @HiveField(9)
  final String? syncAccessCode;
  @HiveField(10)
  final String? syncDecryptionKey;
  @HiveField(11)
  final String? syncServerUrl;
  @HiveField(12)
  final DateTime? lastSyncedAt;
  @HiveField(13)
  final bool isHidden;
  @HiveField(14)
  final String? grantedAccessCode;

  Friend({
    required this.id,
    required this.name,
    required this.privacyLevel,
    required this.timetable,
    required this.addedAt,
    this.profilePicPath,
    this.userId,
    this.isOnlineSync = false,
    this.syncFileId,
    this.syncAccessCode,
    this.syncDecryptionKey,
    this.syncServerUrl,
    this.lastSyncedAt,
    this.isHidden = false,
    this.grantedAccessCode,
  });

  Friend copyWith({
    String? id,
    String? name,
    PrivacyLevel? privacyLevel,
    FriendTimetable? timetable,
    DateTime? addedAt,
    String? profilePicPath,
    String? userId,
    bool? isOnlineSync,
    String? syncFileId,
    String? syncAccessCode,
    String? syncDecryptionKey,
    String? syncServerUrl,
    DateTime? lastSyncedAt,
    bool? isHidden,
    String? grantedAccessCode,
  }) {
    return Friend(
      id: id ?? this.id,
      name: name ?? this.name,
      privacyLevel: privacyLevel ?? this.privacyLevel,
      timetable: timetable ?? this.timetable,
      addedAt: addedAt ?? this.addedAt,
      profilePicPath: profilePicPath ?? this.profilePicPath,
      userId: userId ?? this.userId,
      isOnlineSync: isOnlineSync ?? this.isOnlineSync,
      syncFileId: syncFileId ?? this.syncFileId,
      syncAccessCode: syncAccessCode ?? this.syncAccessCode,
      syncDecryptionKey: syncDecryptionKey ?? this.syncDecryptionKey,
      syncServerUrl: syncServerUrl ?? this.syncServerUrl,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      isHidden: isHidden ?? this.isHidden,
      grantedAccessCode: grantedAccessCode ?? this.grantedAccessCode,
    );
  }
}

/// Exam data for a friend
@HiveType(typeId: 5)
class FriendExam {
  @HiveField(0)
  final String date;
  
  @HiveField(1)
  final String startTime;
  
  @HiveField(2)
  final String finishTime;
  
  @HiveField(3)
  final String subjectDescription;
  
  @HiveField(4)
  final String examRoom;

  FriendExam({
    required this.date,
    required this.startTime,
    required this.finishTime,
    required this.subjectDescription,
    required this.examRoom,
  });

  factory FriendExam.fromExam(exam_models.Exam exam) {
    return FriendExam(
      date: exam.date,
      startTime: exam.startTime,
      finishTime: exam.finishTime,
      subjectDescription: exam.subjectDescription,
      examRoom: exam.examRoom,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'startTime': startTime,
      'finishTime': finishTime,
      'subjectDescription': subjectDescription,
      'examRoom': examRoom,
    };
  }

  factory FriendExam.fromJson(Map<String, dynamic> json) {
    return FriendExam(
      date: json['date'] as String,
      startTime: json['startTime'] as String,
      finishTime: json['finishTime'] as String,
      subjectDescription: json['subjectDescription'] as String,
      examRoom: json['examRoom'] as String,
    );
  }
}

/// Timetable data for a friend (simplified structure)
@HiveType(typeId: 2)
class FriendTimetable {
  @HiveField(0)
  final List<FriendDaySchedule> days;

  @HiveField(1)
  final List<FriendExam>? exams;

  FriendTimetable({required this.days, this.exams});

  /// Convert from full timetable model
  factory FriendTimetable.fromTimetable(
    models.Timetable timetable,
    PrivacyLevel privacyLevel, {
    List<exam_models.Exam>? exams,
  }) {
    // For freeTimeOnly, we convert lessons into free periods (gaps between lessons)
    // so the recipient sees availability windows rather than busy blocks.
    if (privacyLevel == PrivacyLevel.freeTimeOnly) {
      const dayStart = '08:00';
      const dayEnd = '16:00';

      List<FriendDaySchedule> days = timetable.days.map((day) {
        // Collect busy periods in minutes
        final busy = <List<int>>[];
        for (final lesson in day.lessons) {
          try {
            if (lesson.startTime.isEmpty || lesson.endTime.isEmpty) continue;
            final s = parseTimeToMinutes(lesson.startTime);
            final e = parseTimeToMinutes(lesson.endTime);
            if (s != null && e != null && e > s) {
              busy.add([s, e]);
            }
          } catch (_) {
            // ignore parse errors
          }
        }

        busy.sort((a, b) => a[0] - b[0]);

        // Merge overlapping busy periods
        final merged = <List<int>>[];
        for (final b in busy) {
          if (merged.isEmpty) {
            merged.add(List<int>.from(b));
          } else {
            final last = merged.last;
            if (b[0] <= last[1]) {
              // overlap
              last[1] = b[1] > last[1] ? b[1] : last[1];
            } else {
              merged.add(List<int>.from(b));
            }
          }
        }

        // Helper to format minutes back to HH:mm
        String fmt(int minutes) {
          final h = (minutes ~/ 60).toString().padLeft(2, '0');
          final m = (minutes % 60).toString().padLeft(2, '0');
          return '$h:$m';
        }

        final ds = dayStart.split(':');
        final de = dayEnd.split(':');
        final dayS = int.parse(ds[0]) * 60 + int.parse(ds[1]);
        final dayE = int.parse(de[0]) * 60 + int.parse(de[1]);

        final freePeriods = <FriendLesson>[];

        if (merged.isEmpty) {
          freePeriods.add(
            FriendLesson(startTime: dayStart, endTime: dayEnd, name: 'Free'),
          );
        } else {
          // gap before first
          if (merged.first[0] > dayS) {
            freePeriods.add(
              FriendLesson(
                startTime: fmt(dayS),
                endTime: fmt(merged.first[0]),
                name: 'Free',
              ),
            );
          }
          // gaps between
          for (var i = 0; i < merged.length - 1; i++) {
            final endCur = merged[i][1];
            final startNext = merged[i + 1][0];
            if (startNext > endCur) {
              freePeriods.add(
                FriendLesson(
                  startTime: fmt(endCur),
                  endTime: fmt(startNext),
                  name: 'Free',
                ),
              );
            }
          }
          // gap after last
          if (merged.last[1] < dayE) {
            freePeriods.add(
              FriendLesson(
                startTime: fmt(merged.last[1]),
                endTime: fmt(dayE),
                name: 'Free',
              ),
            );
          }
        }

        return FriendDaySchedule(weekday: day.day, lessons: freePeriods);
      }).toList();

      return FriendTimetable(days: days);
    }

    return FriendTimetable(
      days: timetable.days.map((day) {
        return FriendDaySchedule(
          weekday: day.day,
          lessons: day.lessons.map((lesson) {
            return FriendLesson.fromLesson(lesson, privacyLevel);
          }).toList(),
        );
      }).toList(),
      exams: privacyLevel == PrivacyLevel.fullDetails && exams != null 
          ? exams.map((e) => FriendExam.fromExam(e)).toList() 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'days': days.map((d) => d.toJson()).toList(),
      if (exams != null) 'exams': exams!.map((e) => e.toJson()).toList(),
    };
  }

  factory FriendTimetable.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'] as List;
    final days = rawDays
        .map(
          (d) =>
              FriendDaySchedule.fromJson(Map<String, dynamic>.from(d as Map)),
        )
        .toList();

    List<FriendExam>? exams;
    if (json.containsKey('exams') && json['exams'] != null) {
      final rawExams = json['exams'] as List;
      exams = rawExams
          .map(
            (e) => FriendExam.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    }

    return FriendTimetable(days: days, exams: exams);
  }
}

@HiveType(typeId: 3)
class FriendDaySchedule {
  @HiveField(0)
  final String weekday;

  @HiveField(1)
  final List<FriendLesson> lessons;

  FriendDaySchedule({required this.weekday, required this.lessons});

  Map<String, dynamic> toJson() {
    return {
      'weekday': weekday,
      'lessons': lessons.map((l) => l.toJson()).toList(),
    };
  }

  factory FriendDaySchedule.fromJson(Map<String, dynamic> json) {
    final rawLessons = json['lessons'] as List;
    final lessons = rawLessons
        .map((l) => FriendLesson.fromJson(Map<String, dynamic>.from(l as Map)))
        .toList();
    return FriendDaySchedule(
      weekday: json['weekday'] as String,
      lessons: lessons,
    );
  }
}

@HiveType(typeId: 4)
class FriendLesson {
  @HiveField(0)
  final String startTime;

  @HiveField(1)
  final String endTime;

  @HiveField(2)
  final String? name; // null if privacy level is freeTimeOnly or busyBlocks

  @HiveField(3)
  final String? room; // null if privacy level is not fullDetails

  @HiveField(4)
  final String? courseCode; // null if privacy level is not fullDetails

  FriendLesson({
    required this.startTime,
    required this.endTime,
    this.name,
    this.room,
    this.courseCode,
  });

  factory FriendLesson.fromLesson(
    models.Lesson lesson,
    PrivacyLevel privacyLevel,
  ) {
    switch (privacyLevel) {
      case PrivacyLevel.freeTimeOnly:
        // This shouldn't be called for free time only, but handle it
        return FriendLesson(
          startTime: lesson.startTime,
          endTime: lesson.endTime,
        );
      case PrivacyLevel.busyBlocks:
        return FriendLesson(
          startTime: lesson.startTime,
          endTime: lesson.endTime,
          name: 'Busy', // Generic placeholder
        );
      case PrivacyLevel.fullDetails:
        return FriendLesson(
          startTime: lesson.startTime,
          endTime: lesson.endTime,
          name: lesson.name,
          room: lesson.room,
          courseCode: lesson.course,
        );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'startTime': startTime,
      'endTime': endTime,
      if (name != null) 'name': name,
      if (room != null) 'room': room,
      if (courseCode != null) 'courseCode': courseCode,
    };
  }

  factory FriendLesson.fromJson(Map<String, dynamic> json) {
    return FriendLesson(
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
      name: json['name'] as String?,
      room: json['room'] as String?,
      courseCode: json['courseCode'] as String?,
    );
  }
}

/// Represents a mutual gap (free time for both users)
class MutualGap {
  final String weekday;
  final String startTime;
  final String endTime;
  final Duration duration;

  MutualGap({
    required this.weekday,
    required this.startTime,
    required this.endTime,
    required this.duration,
  });
}

/// Helper to parse standard 12-hour or 24-hour time strings to minutes since midnight
int? parseTimeToMinutes(String timeString) {
  try {
    final clean = timeString.trim();
    if (clean.isEmpty) return null;
    final upper = clean.toUpperCase();
    final isPM = upper.contains('PM');
    final isAM = upper.contains('AM');

    final digitsOnly = upper.replaceAll(RegExp(r'[^0-9:]'), '');
    final parts = digitsOnly.split(':');
    if (parts.length >= 2) {
      var hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      if (isPM && hour < 12) {
        hour += 12;
      } else if (isAM && hour == 12) {
        hour = 0;
      }
      return hour * 60 + minute;
    }
  } catch (_) {}
  return null;
}

