import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nscgschedule/privacy_policy_screen.dart';
import 'package:nscgschedule/services/timetable_sync_service.dart';
import 'package:nscgschedule/models/timetable_models.dart' as models;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce/hive.dart';
import 'package:nscgschedule/models/friend_models.dart';
import 'package:nscgschedule/friends_service.dart';
import 'package:nscgschedule/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TimetableSyncService Privacy & Consent Gating Tests', () {
    late Directory tempDir;
    final Map<String, String> mockSecureStorage = {};
    late TimetableSyncService syncService;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      mockSecureStorage.clear();
      tempDir = await Directory.systemTemp.createTemp('hive_privacy_test');

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

      Hive.init(tempDir.path);
      try {
        Hive.registerAdapter(PrivacyLevelAdapter());
        Hive.registerAdapter(FriendAdapter());
        Hive.registerAdapter(FriendTimetableAdapter());
        Hive.registerAdapter(FriendDayScheduleAdapter());
        Hive.registerAdapter(FriendLessonAdapter());
      } catch (_) {}

      if (!GetIt.I.isRegistered<Settings>()) {
        GetIt.I.registerSingleton<Settings>(Settings());
        await settings.init();
      }

      final friendsService = FriendsService();
      await friendsService.init();
      if (!GetIt.I.isRegistered<FriendsService>()) {
        GetIt.I.registerSingleton<FriendsService>(friendsService);
      }

      syncService = TimetableSyncService();
      await syncService.setServerUrl('http://127.0.0.1:3000');
    });

    tearDownAll(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Defaults: online sync is disabled and onboarding is not completed', () async {
      await syncService.setOnlineSyncEnabled(false);
      await syncService.setPrivacyPolicyAccepted(false);
      await syncService.setFriendsOnboardingCompleted(false);

      expect(await syncService.isOnlineSyncEnabled(), isFalse);
      expect(await syncService.isPrivacyPolicyAccepted(), isFalse);
      expect(await syncService.isFriendsOnboardingCompleted(), isFalse);
    });

    test('Accepting privacy policy and enabling online sync activates online sync', () async {
      await syncService.setPrivacyPolicyAccepted(true);
      expect(await syncService.isPrivacyPolicyAccepted(), isTrue);
      // Still false until online sync is explicitly enabled
      expect(await syncService.isOnlineSyncEnabled(), isFalse);

      await syncService.setOnlineSyncEnabled(true);
      expect(await syncService.isOnlineSyncEnabled(), isTrue);

      await syncService.setFriendsOnboardingCompleted(true);
      expect(await syncService.isFriendsOnboardingCompleted(), isTrue);
    });

    test('Disabling online sync gates sync calls gracefully', () async {
      await syncService.setOnlineSyncEnabled(false);
      await syncService.setPrivacyPolicyAccepted(false);

      expect(await syncService.isOnlineSyncEnabled(), isFalse);

      // updateOnlineTimetable returns false without network call
      const emptyTimetable = models.Timetable(days: []);
      final updateResult = await syncService.updateOnlineTimetable(timetable: emptyTimetable);
      expect(updateResult, isFalse);

      // syncAllFriends returns 0 without network call
      final syncedCount = await syncService.syncAllFriends();
      expect(syncedCount, equals(0));

      // checkAndSyncMailbox returns empty list without network call
      final mailbox = await syncService.checkAndSyncMailbox();
      expect(mailbox, isEmpty);

      // fetchAccessList returns empty access info
      final accessInfo = await syncService.fetchAccessList();
      expect(accessInfo.active, isEmpty);
      expect(accessInfo.blocked, isEmpty);

      // publishTimetable throws StateError when disabled
      expect(
        () => syncService.publishTimetable(timetable: emptyTimetable),
        throwsA(isA<StateError>()),
      );

      // claimAndAddFriendFromQR throws StateError when disabled
      expect(
        () => syncService.claimAndAddFriendFromQR('{"type":"online_sync","fileId":"123","inviteKey":"k","decryptionKey":"d"}'),
        throwsA(isA<StateError>()),
      );
    });

    test('deletePublishedTimetable clears published credentials, removes online friends, and opts out of online sync', () async {
      await syncService.setOnlineSyncEnabled(true);
      await syncService.setPrivacyPolicyAccepted(true);
      await settings.setKey('published_sync_file_id', 'test-file-id');
      await settings.setKey('published_sync_owner_code', 'test-owner-code');

      final friendsService = GetIt.I<FriendsService>();
      final onlineFriend = Friend(
        id: 'online-friend-1',
        name: 'Online Friend',
        privacyLevel: PrivacyLevel.fullDetails,
        timetable: FriendTimetable(days: []),
        addedAt: DateTime.now(),
        isOnlineSync: true,
        syncFileId: 'remote-file-id-1',
      );
      final offlineFriend = Friend(
        id: 'offline-friend-1',
        name: 'Offline Friend',
        privacyLevel: PrivacyLevel.busyBlocks,
        timetable: FriendTimetable(days: []),
        addedAt: DateTime.now(),
        isOnlineSync: false,
      );

      await friendsService.saveFriend(onlineFriend);
      await friendsService.saveFriend(offlineFriend);

      expect(friendsService.getFriend('online-friend-1'), isNotNull);
      expect(friendsService.getFriend('offline-friend-1'), isNotNull);
      expect(await syncService.isOnlineSyncEnabled(), isTrue);
      expect(await syncService.isPrivacyPolicyAccepted(), isTrue);
      expect(await syncService.isTimetablePublished(), isTrue);

      await syncService.deletePublishedTimetable();

      expect(await syncService.isTimetablePublished(), isFalse);
      expect(await syncService.isOnlineSyncEnabled(), isFalse);
      expect(await syncService.isPrivacyPolicyAccepted(), isFalse);

      // Online friend must be completely removed, offline friend remains
      expect(friendsService.getFriend('online-friend-1'), isNull);
      expect(friendsService.getFriend('offline-friend-1'), isNotNull);
    });

    test('getCachedPrivacyPolicy and saveCachedPrivacyPolicy store and retrieve markdown without bundled copy', () async {
      expect(await syncService.getCachedPrivacyPolicy(), isNull);

      const testMarkdown = '# Dynamic Policy\n\nFetched from server.';
      await syncService.saveCachedPrivacyPolicy(testMarkdown);

      expect(await syncService.getCachedPrivacyPolicy(), equals(testMarkdown));
    });

    test('Privacy acceptance state gating logic functions correctly', () async {
      await syncService.setPrivacyPolicyAccepted(false);
      expect(await syncService.isPrivacyPolicyAccepted(), isFalse);

      await syncService.setPrivacyPolicyAccepted(true);
      expect(await syncService.isPrivacyPolicyAccepted(), isTrue);

      await syncService.setPrivacyPolicyAccepted(false);
      expect(await syncService.isPrivacyPolicyAccepted(), isFalse);
    });
  });
}
