import 'package:flutter_test/flutter_test.dart';
import 'package:nscgschedule/services/timetable_sync_service.dart';
import 'package:nscgschedule/models/friend_models.dart';
import 'package:nscgschedule/models/timetable_models.dart' as models;
import 'dart:convert';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TimetableSyncService Cryptography & QR Tests', () {
    final syncService = TimetableSyncService();

    test('ChaCha20-Poly1305 key generation, encryption, and decryption', () async {
      final key = await syncService.generateKey();
      expect(key.isNotEmpty, isTrue);

      const sampleJson = '{"name":"Test User","lessons":[{"title":"Math","room":"A101"}]}';
      final encrypted = await syncService.encryptString(sampleJson, key);
      expect(encrypted.isNotEmpty, isTrue);
      expect(encrypted != sampleJson, isTrue);

      final decrypted = await syncService.decryptString(encrypted, key);
      expect(decrypted, equals(sampleJson));
    });

    test('Online Sync QR format detection and validation', () {
      expect(syncService.isOnlineSyncQR('v2:sync:abc12345'), isTrue);
      expect(syncService.isOnlineSyncQR('v2:abc12345'), isFalse);
      expect(syncService.isOnlineSyncQR('some random text'), isFalse);
    });

    test('Online Sync QR payload compression and decompression', () {
      final payloadData = {
        'fileId': 'file-123',
        'inviteKey': 'inv-abc',
        'decryptionKey': 'dkey-xyz',
        'serverUrl': 'http://192.168.1.106:3000',
        'privacyLevel': 'fullDetails',
        'name': 'Alice',
        'userId': 'user-alice-1',
      };

      final jsonStr = jsonEncode(payloadData);
      final gzipped = gzip.encode(utf8.encode(jsonStr));
      final qrString = 'v2:sync:${base64Url.encode(gzipped)}';

      expect(syncService.isOnlineSyncQR(qrString), isTrue);

      final stripped = qrString.substring('v2:sync:'.length);
      final decompressedBytes = gzip.decode(base64Url.decode(stripped));
      final decodedJson = jsonDecode(utf8.decode(decompressedBytes)) as Map<String, dynamic>;

      expect(decodedJson['fileId'], equals('file-123'));
      expect(decodedJson['inviteKey'], equals('inv-abc'));
      expect(decodedJson['decryptionKey'], equals('dkey-xyz'));
      expect(decodedJson['name'], equals('Alice'));
    });

    test('parseTimeToMinutes handles 12h AM/PM and 24h formats accurately', () {
      expect(parseTimeToMinutes('09:00'), equals(540));
      expect(parseTimeToMinutes('9:00 AM'), equals(540));
      expect(parseTimeToMinutes('12:00 PM'), equals(720));
      expect(parseTimeToMinutes('12:00 AM'), equals(0));
      expect(parseTimeToMinutes('1:30 PM'), equals(810));
      expect(parseTimeToMinutes('13:30'), equals(810));
      expect(parseTimeToMinutes('04:45 PM'), equals(1005));
    });

    test('FriendTimetable.fromTimetable generates valid schedules for all privacy levels', () {
      final mockTimetable = models.Timetable(
        days: [
          models.DaySchedule(
            day: 'Monday',
            lessons: [
              models.Lesson(
                course: 'CS101',
                group: 'A',
                name: 'Computer Science',
                startTime: '09:00 AM',
                endTime: '10:30 AM',
                room: 'Lab 1',
                teachers: ['Dr. Smith'],
              ),
              models.Lesson(
                course: 'MATH201',
                group: 'B',
                name: 'Calculus',
                startTime: '01:00 PM',
                endTime: '02:30 PM',
                room: 'Room 204',
                teachers: ['Prof. Jones'],
              ),
            ],
          ),
        ],
      );

      // 1. Full Details
      final full = FriendTimetable.fromTimetable(mockTimetable, PrivacyLevel.fullDetails);
      expect(full.days.first.lessons.length, equals(2));
      expect(full.days.first.lessons[0].name, equals('Computer Science'));
      expect(full.days.first.lessons[0].room, equals('Lab 1'));

      // 2. Busy Blocks
      final busy = FriendTimetable.fromTimetable(mockTimetable, PrivacyLevel.busyBlocks);
      expect(busy.days.first.lessons.length, equals(2));
      expect(busy.days.first.lessons[0].name, equals('Busy'));
      expect(busy.days.first.lessons[0].room, isNull);

      // 3. Free Time Only
      final free = FriendTimetable.fromTimetable(mockTimetable, PrivacyLevel.freeTimeOnly);
      expect(free.days.first.lessons.isNotEmpty, isTrue);
      expect(free.days.first.lessons[0].name, equals('Free'));
    });
  });
}

