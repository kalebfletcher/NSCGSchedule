import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nscgschedule/debug_service.dart';
import 'package:nscgschedule/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DebugService Mock Generator Tests', () {
    late Directory tempDir;
    final Map<String, String> mockSecureStorage = {};

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      mockSecureStorage.clear();
      tempDir = await Directory.systemTemp.createTemp('hive_mock_test');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (MethodCall methodCall) async {
              if (methodCall.method == 'getApplicationSupportDirectory' ||
                  methodCall.method == 'getApplicationDocumentsDirectory') {
                return tempDir.path;
              }
              return null;
            },
          );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (MethodCall methodCall) async {
              final args = methodCall.arguments as Map<dynamic, dynamic>?;
              final key = args?['key'] as String?;
              if (methodCall.method == 'read') {
                return mockSecureStorage[key];
              } else if (methodCall.method == 'write') {
                final value = args?['value'] as String?;
                if (key != null && value != null) {
                  mockSecureStorage[key] = value;
                }
                return null;
              } else if (methodCall.method == 'delete') {
                if (key != null) mockSecureStorage.remove(key);
                return null;
              } else if (methodCall.method == 'deleteAll') {
                mockSecureStorage.clear();
                return null;
              }
              return null;
            },
          );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('generateRandomTimetable creates valid schedule and saves to settings', () async {
      final service = DebugService.instance;
      final timetable = await service.generateRandomTimetable();

      expect(timetable.days.isNotEmpty, isTrue);
      expect(timetable.days.length, equals(5));

      for (final day in timetable.days) {
        expect(day.lessons.isNotEmpty, isTrue);
        for (final lesson in day.lessons) {
          expect(lesson.name.isNotEmpty, isTrue);
          expect(lesson.startTime.isNotEmpty, isTrue);
          expect(lesson.endTime.isNotEmpty, isTrue);
          expect(lesson.room.isNotEmpty, isTrue);
        }
      }

      final settings = Settings();
      final savedTt = await settings.getMap('timetable');
      expect(savedTt.isNotEmpty, isTrue);
      expect(savedTt['days'], isNotNull);
    });

    test('generateRandomExamTimetable creates valid exam timetable and saves to settings', () async {
      final service = DebugService.instance;
      final examTimetable = await service.generateRandomExamTimetable();

      expect(examTimetable.hasExams, isTrue);
      expect(examTimetable.studentInfo, isNotNull);
      expect(examTimetable.studentInfo!.name, equals('Alex Morgan'));
      expect(examTimetable.exams.isNotEmpty, isTrue);

      for (final exam in examTimetable.exams) {
        expect(exam.date.isNotEmpty, isTrue);
        expect(exam.parsedDate, isNotNull);
        expect(exam.subjectDescription.isNotEmpty, isTrue);
        expect(exam.startTime.isNotEmpty, isTrue);
        expect(exam.finishTime.isNotEmpty, isTrue);
      }

      final settings = Settings();
      final savedExams = await settings.getMap('examTimetable');
      expect(savedExams.isNotEmpty, isTrue);
      expect(savedExams['hasExams'], isTrue);
    });

    test('mock generation does not override existing user identity', () async {
      final settings = Settings();
      await settings.setKey('timetableOwner', 'Jane Doe');
      await settings.setKey('timetableOwnerRef', '998877');
      await settings.setKey('timetableOwnerId', 'C998877');

      final service = DebugService.instance;
      await service.generateRandomTimetable();

      expect(await settings.getKey('timetableOwner'), equals('Jane Doe'));
      expect(await settings.getKey('timetableOwnerRef'), equals('998877'));
      expect(await settings.getKey('timetableOwnerId'), equals('C998877'));

      final examTimetable = await service.generateRandomExamTimetable();
      expect(examTimetable.studentInfo?.name, equals('Jane Doe'));
      expect(examTimetable.studentInfo?.refNo, equals('998877'));
    });
  });
}
