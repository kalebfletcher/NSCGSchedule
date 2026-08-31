import 'dart:convert';
import 'dart:io' show gzip;
import 'package:hive_ce/hive.dart';
import 'package:nscgschedule/models/friend_models.dart';
import 'package:nscgschedule/models/timetable_models.dart' as models;

class FriendsService {
  static const String _friendsBoxName = 'friends';

  late Box<Friend> _friendsBox;

  bool _initialized = false;

  /// Initialize the service and open Hive boxes
  Future<void> init() async {
    if (_initialized) return;

    _friendsBox = await Hive.openBox<Friend>(_friendsBoxName);
    
    // Automatic cleanup of duplicate friends by userId
    final allFriends = _friendsBox.values.toList();
    final groupedByUserIds = <String, List<Friend>>{};
    
    for (final f in allFriends) {
      if (f.userId != null && f.userId!.isNotEmpty) {
        groupedByUserIds.putIfAbsent(f.userId!, () => []).add(f);
      }
    }
    
    for (final duplicates in groupedByUserIds.values) {
      if (duplicates.length > 1) {
        // Find best match (prefer visible)
        final best = duplicates.firstWhere((f) => !f.isHidden, orElse: () => duplicates.first);
        
        // Merge grantedAccessCode if any of the matches have it
        final mergedAccessCode = duplicates.map((f) => f.grantedAccessCode).firstWhere((code) => code != null, orElse: () => null);
        
        if (mergedAccessCode != null && best.grantedAccessCode != mergedAccessCode) {
           await _friendsBox.put(best.id, best.copyWith(grantedAccessCode: mergedAccessCode));
        }
        
        // Delete all other duplicates
        for (final f in duplicates) {
          if (f.id != best.id) {
            await _friendsBox.delete(f.id);
          }
        }
      }
    }
    
    _initialized = true;
  }

  /// Get all saved friends
  List<Friend> getAllFriends({bool includeHidden = false}) {
    final all = _friendsBox.values.toList();
    if (includeHidden) return all;
    return all.where((f) => !f.isHidden).toList();
  }

  /// Get a specific friend by ID
  Friend? getFriend(String id) {
    return _friendsBox.get(id);
  }

  /// Add or update a friend
  Future<void> saveFriend(Friend friend) async {
    await _friendsBox.put(friend.id, friend);
  }

  /// Delete a friend
  Future<void> deleteFriend(String id) async {
    await _friendsBox.delete(id);
  }

  /// Generate QR code data from user's timetable with selected privacy level
  String generateQRData({
    required String userName,
    required models.Timetable timetable,
    required PrivacyLevel privacyLevel,
    String? userId,
  }) {
    final friendTimetable = FriendTimetable.fromTimetable(
      timetable,
      privacyLevel,
    );

    // Create a unique ID for this share
    final shareId = DateTime.now().millisecondsSinceEpoch.toString();

    final data = {
      'version': 1, // For future compatibility
      'id': shareId,
      'name': userName,
      'userId': ?userId,
      'privacyLevel': privacyLevel.index,
      'timetable': friendTimetable.toJson(),
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Serialize JSON and compress with gzip, then base64-url encode to keep QR size small.
    // Prefix with a version marker so the parser can detect compressed payloads.
    final jsonStr = jsonEncode(data);
    final bytes = utf8.encode(jsonStr);
    final compressed = gzip.encode(bytes);
    final encoded = base64UrlEncode(compressed);
    return 'v1:$encoded';
  }

  /// Parse scanned QR code data and create a Friend object
  Friend? parseQRData(String qrData) {
    try {
      // Support both plain JSON (legacy) and compressed payloads prefixed with "v1:"
      String jsonString;
      final trimmed = qrData.trim();
      if (trimmed.startsWith('v1:')) {
        final b64 = trimmed.substring(3);
        final compressed = base64Url.decode(b64);
        final decompressed = gzip.decode(compressed);
        jsonString = utf8.decode(decompressed);
      } else if (trimmed.startsWith('{')) {
        jsonString = trimmed;
      } else {
        // Unknown format
        return null;
      }

      final json = Map<String, dynamic>.from(jsonDecode(jsonString) as Map);

      // Validate version
      if (json['version'] != 1) {
        return null;
      }

      final id = json['id'] as String;
      final name = json['name'] as String;
      final userId = json.containsKey('userId')
          ? (json['userId'] as String?)
          : null;
      final privacyIndex = json['privacyLevel'] as int;
      final privacyLevel = PrivacyLevel.values[privacyIndex];
      final timetableJson = Map<String, dynamic>.from(json['timetable'] as Map);

      final friendTimetable = FriendTimetable.fromJson(timetableJson);

      return Friend(
        id: id,
        name: name,
        userId: userId,
        privacyLevel: privacyLevel,
        timetable: friendTimetable,
        addedAt: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Find mutual free time gaps between user and a friend
  List<MutualGap> findMutualGaps({
    required models.Timetable userTimetable,
    required Friend friend,
  }) {
    final gaps = <MutualGap>[];

    // School day bounds (adjust as needed)
    const schoolStart = '08:00';
    const schoolEnd = '16:00';

    for (var i = 0; i < userTimetable.days.length; i++) {
      final userDay = userTimetable.days[i];
      final friendDay = friend.timetable.days.firstWhere(
        (d) => d.weekday == userDay.day,
        orElse: () => FriendDaySchedule(weekday: userDay.day, lessons: []),
      );

      // Get all busy periods for the user
      final userBusyPeriods = userDay.lessons
          .map((l) => _TimePeriod(l.startTime, l.endTime))
          .toList();

      // Find free periods for user
      final userFreePeriods = _findFreePeriods(
        userBusyPeriods,
        schoolStart,
        schoolEnd,
      );

      // For friends, respect their privacy encoding:
      // - If they shared `freeTimeOnly`, their `lessons` are already free periods.
      // - Otherwise, their `lessons` are busy periods and we compute free periods from them.
      List<_TimePeriod> friendFreePeriods;
      if (friend.privacyLevel == PrivacyLevel.freeTimeOnly) {
        friendFreePeriods = friendDay.lessons
            .map((l) => _TimePeriod(l.startTime, l.endTime))
            .toList();
      } else {
        final friendBusyPeriods = friendDay.lessons
            .map((l) => _TimePeriod(l.startTime, l.endTime))
            .toList();
        friendFreePeriods = _findFreePeriods(
          friendBusyPeriods,
          schoolStart,
          schoolEnd,
        );
      }

      // Find overlapping free periods
      for (final userFree in userFreePeriods) {
        for (final friendFree in friendFreePeriods) {
          final overlap = _findOverlap(userFree, friendFree);
          if (overlap != null) {
            final duration = _calculateDuration(
              overlap.startTime,
              overlap.endTime,
            );
            // Only include gaps of at least 15 minutes
            if (duration.inMinutes >= 15) {
              gaps.add(
                MutualGap(
                  weekday: userDay.day,
                  startTime: overlap.startTime,
                  endTime: overlap.endTime,
                  duration: duration,
                ),
              );
            }
          }
        }
      }
    }

    return gaps;
  }

  /// Find free periods in a day given busy periods
  List<_TimePeriod> _findFreePeriods(
    List<_TimePeriod> busyPeriods,
    String dayStart,
    String dayEnd,
  ) {
    if (busyPeriods.isEmpty) {
      return [_TimePeriod(dayStart, dayEnd)];
    }

    // Sort busy periods by start time
    final sorted = List<_TimePeriod>.from(busyPeriods)
      ..sort((a, b) => _compareTime(a.startTime, b.startTime));

    final freePeriods = <_TimePeriod>[];

    // Check gap before first lesson
    if (_compareTime(sorted.first.startTime, dayStart) > 0) {
      freePeriods.add(_TimePeriod(dayStart, sorted.first.startTime));
    }

    // Check gaps between lessons
    for (var i = 0; i < sorted.length - 1; i++) {
      final current = sorted[i];
      final next = sorted[i + 1];

      if (_compareTime(next.startTime, current.endTime) > 0) {
        freePeriods.add(_TimePeriod(current.endTime, next.startTime));
      }
    }

    // Check gap after last lesson
    if (_compareTime(dayEnd, sorted.last.endTime) > 0) {
      freePeriods.add(_TimePeriod(sorted.last.endTime, dayEnd));
    }

    return freePeriods;
  }

  /// Find overlap between two time periods
  _TimePeriod? _findOverlap(_TimePeriod a, _TimePeriod b) {
    final latestStart = _compareTime(a.startTime, b.startTime) > 0
        ? a.startTime
        : b.startTime;
    final earliestEnd = _compareTime(a.endTime, b.endTime) < 0
        ? a.endTime
        : b.endTime;

    if (_compareTime(latestStart, earliestEnd) < 0) {
      return _TimePeriod(latestStart, earliestEnd);
    }
    return null;
  }

  /// Compare two time strings
  int _compareTime(String time1, String time2) {
    final m1 = parseTimeToMinutes(time1) ?? 0;
    final m2 = parseTimeToMinutes(time2) ?? 0;
    return m1 - m2;
  }

  /// Calculate duration between two times
  Duration _calculateDuration(String startTime, String endTime) {
    final m1 = parseTimeToMinutes(startTime) ?? 0;
    final m2 = parseTimeToMinutes(endTime) ?? 0;
    return Duration(minutes: m2 - m1);
  }
}

/// Helper class for time periods
class _TimePeriod {
  final String startTime;
  final String endTime;

  _TimePeriod(this.startTime, this.endTime);
}
