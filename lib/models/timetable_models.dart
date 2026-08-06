import 'package:html/parser.dart' show parse;

class Timetable {
  final List<DaySchedule> days;

  const Timetable({required this.days});

  factory Timetable.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'] as List;
    final days = rawDays
        .map(
          (dayJson) =>
              DaySchedule.fromJson(Map<String, dynamic>.from(dayJson as Map)),
        )
        .toList();
    return Timetable(days: days);
  }

  Map<String, dynamic> toJson() {
    return {'days': days.map((day) => day.toJson()).toList()};
  }

  factory Timetable.fromHtml(String html) {
    final document = parse(html);

    // Build a mapping of top position (px) -> time string
    final topToTime = <double, String>{};
    final timeItems = document.querySelectorAll('div.ttItemTimes');
    for (final item in timeItems) {
      final style = item.attributes['style'] ?? '';
      final topMatch = RegExp(r'top:\s*([0-9]*\.?[0-9]+)px').firstMatch(style);
      if (topMatch != null) {
        final top = double.tryParse(topMatch.group(1) ?? '');
        if (top != null) {
          final timeText = item.text.trim();
          topToTime[top] = timeText;
        }
      }
    }

    // Helper to find time for a given top position
    String? timeForTop(double top) {
      // Find exact match or closest time entry
      if (topToTime.containsKey(top)) return topToTime[top];
      // Find closest
      double? closest;
      double minDiff = double.infinity;
      for (final key in topToTime.keys) {
        final diff = (key - top).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closest = key;
        }
      }
      return closest != null ? topToTime[closest] : null;
    }

    // Map of left percentage -> weekday name
    final dayPositions = <int, String>{
      6: 'Monday',
      24: 'Tuesday',
      42: 'Wednesday',
      60: 'Thursday',
      78: 'Friday',
    };

    String? weekdayForLeft(String leftStr) {
      final match = RegExp(r'(\d+)%').firstMatch(leftStr);
      if (match != null) {
        final leftPercent = int.tryParse(match.group(1) ?? '');
        if (leftPercent != null) {
          return dayPositions[leftPercent];
        }
      }
      return null;
    }

    final daysMap = <String, List<Lesson>>{};

    final items = document.querySelectorAll('div.ttItem');
    for (final item in items) {
      final classes = item.className;
      if (classes.contains('ttItemTimes') || classes.contains('ttItemDays')) {
        continue;
      }

      final style = item.attributes['style'] ?? '';
      final leftMatch = RegExp(r'left:\s*([^;]+);').firstMatch(style);
      if (leftMatch == null) continue;
      final leftStr = leftMatch.group(1) ?? '';

      final weekday = weekdayForLeft(leftStr);
      if (weekday == null) continue;

      // Parse top and height to determine start and end times
      final topMatch = RegExp(r'top:\s*([0-9]*\.?[0-9]+)px').firstMatch(style);
      final heightMatch = RegExp(
        r'height:\s*([0-9]*\.?[0-9]+)px',
      ).firstMatch(style);

      String startTime = '';
      String endTime = '';
      if (topMatch != null && heightMatch != null) {
        final top = double.tryParse(topMatch.group(1) ?? '');
        final height = double.tryParse(heightMatch.group(1) ?? '');
        if (top != null && height != null) {
          startTime = timeForTop(top) ?? '';
          endTime = timeForTop(top + height) ?? '';
        }
      }

      // Parse the lesson content - replace <br> tags with newlines first
      final inner = item.innerHtml.replaceAll(
        RegExp(r'<br\s*/?>', caseSensitive: false),
        '\n',
      );
      final text = parse(inner).body?.text ?? inner;
      final lines = text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (lines.isEmpty) continue;

      final name = lines[0];

      String courseCode = '';
      String group = '';
      List<String> teachers = [];

      if (lines.length >= 2) {
        final parts = lines[1].split(RegExp(r'\s+'));
        if (parts.isNotEmpty) {
          courseCode = parts[0];
          if (parts.length >= 2) group = parts[1];
          if (parts.length > 2) {
            teachers = parts
                .sublist(2)
                .join(' ')
                .split(RegExp(r',\s*| and '))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
        }
      }

      // Extract room from "ROOM: XXXXX" pattern
      String room = '';
      final roomMatch = RegExp(
        r'ROOM:\s*([^\s<]+)',
        caseSensitive: false,
      ).firstMatch(inner);
      if (roomMatch != null) {
        room = roomMatch.group(1)?.trim() ?? '';
      }

      final lesson = Lesson(
        teachers: teachers,
        course: courseCode,
        group: group,
        name: name,
        startTime: startTime,
        endTime: endTime,
        room: room,
      );

      daysMap.putIfAbsent(weekday, () => []).add(lesson);
    }

    final order = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final days = <DaySchedule>[];
    for (final dayName in order) {
      if (daysMap.containsKey(dayName)) {
        days.add(DaySchedule(day: dayName, lessons: daysMap[dayName]!));
      }
    }

    return Timetable(days: days);
  }

  /// Try to extract the timetable owner's name from the raw HTML returned
  /// by the student timetable page. Returns `null` if no clear owner name
  /// can be located.
  static String? extractOwnerName(String html) {
    final document = parse(html);

    String normalizeName(String s) {
      return s.replaceAll(RegExp(r"\s+"), ' ').trim();
    }

    // Look for an <h3> that contains the phrase "Your Timetable" and
    // prefer a contained <span> if present (many pages put the name in a span).
    final headers = document.querySelectorAll('h3');
    for (final h in headers) {
      final text = h.text.trim();
      if (text.contains('Your Timetable')) {
        final span = h.querySelector('span');
        if (span != null) {
          final s = normalizeName(span.text);
          if (s.isNotEmpty) {
            return s;
          }
        }

        // Fallback: take the portion of the header before the phrase
        // "Your Timetable" as the name.
        final idx = text.indexOf('Your Timetable');
        if (idx > 0) {
          var name = text.substring(0, idx);
          // Strip stray punctuation at the end and collapse whitespace
          name = name.replaceAll(RegExp(r"[\-:,]+"), ' ');
          name = normalizeName(name);
          if (name.isNotEmpty) {
            return name;
          }
        }
      }
    }

    // Check all headers (h1, h2, h3, h4) for "Welcome, <Name>" or "<Name>'s Timetable"
    final allHeaders = document.querySelectorAll('h1, h2, h3, h4');
    for (final h in allHeaders) {
      final text = normalizeName(h.text);
      final welcomeMatch = RegExp(
        r"Welcome,?\s+([A-Za-z\s'-]+)",
        caseSensitive: false,
      ).firstMatch(text);
      if (welcomeMatch != null) {
        final name = welcomeMatch.group(1)?.trim() ?? '';
        if (name.isNotEmpty) {
          return name;
        }
      }
      final apostropheMatch = RegExp(
        r"^([A-Za-z\s'-]+)'s\s+Timetable",
        caseSensitive: false,
      ).firstMatch(text);
      if (apostropheMatch != null) {
        final name = apostropheMatch.group(1)?.trim() ?? '';
        if (name.isNotEmpty) {
          return name;
        }
      }
    }

    // As a last-ditch fallback try the <title> if it looks like a personal
    // timetable title that includes a name.
    final title = document.querySelector('title')?.text;
    if (title != null) {
      final t = normalizeName(title);
      if (t.isNotEmpty && !t.toLowerCase().contains('timetable')) {
        return t;
      }
    }

    return null;
  }
}

class DaySchedule {
  final String day;
  final List<Lesson> lessons;

  const DaySchedule({required this.day, required this.lessons});

  factory DaySchedule.fromJson(Map<String, dynamic> json) {
    final rawLessons = json['lessons'] as List;
    final lessons = rawLessons
        .map(
          (lessonJson) =>
              Lesson.fromJson(Map<String, dynamic>.from(lessonJson as Map)),
        )
        .toList();
    return DaySchedule(day: json['day'] as String, lessons: lessons);
  }

  Map<String, dynamic> toJson() {
    return {
      'day': day,
      'lessons': lessons.map((lesson) => lesson.toJson()).toList(),
    };
  }

  @override
  String toString() => 'DaySchedule($day, ${lessons.length} lessons)';
}

class Lesson {
  final List<String> teachers;
  final String course;
  final String group;
  final String name;
  final String startTime;
  final String endTime;
  final String room;

  factory Lesson.fromJson(Map<String, dynamic> json) {
    return Lesson(
      teachers: List<String>.from(json['teachers'] as List),
      course: json['course'] as String,
      group: json['group'] as String,
      name: json['name'] as String,
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
      room: json['room'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'teachers': teachers,
      'course': course,
      'group': group,
      'name': name,
      'startTime': startTime,
      'endTime': endTime,
      'room': room,
    };
  }

  const Lesson({
    required this.teachers,
    required this.course,
    required this.group,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.room,
  });

  @override
  String toString() {
    return 'Lesson($name, $startTime-$endTime, $room, ${teachers.join(', ')})';
  }
}
