import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:nscgschedule/friends_service.dart';
import 'package:nscgschedule/models/friend_models.dart';
import 'package:nscgschedule/models/timetable_models.dart' as models;
import 'package:nscgschedule/settings.dart';
import 'package:nscgschedule/models/exam_models.dart' as exam_models;
import 'package:uuid/uuid.dart';

class TimetableSyncService {
  static const String defaultServerUrl = 'https://nscgsync.kaleb.lol';
  static const String _syncServerUrlKey = 'sync_server_url';
  static const String _deviceIdKey = 'device_unique_id';
  static const String _onlineSyncEnabledKey = 'online_sync_enabled';
  static const String _privacyPolicyAcceptedKey = 'privacy_policy_accepted';
  static const String _friendsOnboardingCompletedKey = 'friends_onboarding_completed';

  static const String _publishedFileIdKey = 'published_sync_file_id';
  static const String _publishedOwnerCodeKey = 'published_sync_owner_code';
  static const String _publishedKeyAll = 'published_sync_key_all';
  static const String _publishedKeyBusy = 'published_sync_key_busy';
  static const String _publishedKeyFree = 'published_sync_key_free';
  static const String _publishedInviteAll = 'published_sync_invite_all';
  static const String _publishedInviteBusy = 'published_sync_invite_busy';
  static const String _publishedInviteFree = 'published_sync_invite_free';
  static const String _publishedMailboxKey = 'published_sync_mailbox_key';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  final Cipher _cipher = Chacha20.poly1305Aead();

  /// Get current configured sync server URL
  Future<String> getServerUrl() async {
    final customUrl = await settings.getKey(_syncServerUrlKey);
    if (customUrl.isNotEmpty) {
      return customUrl.endsWith('/')
          ? customUrl.substring(0, customUrl.length - 1)
          : customUrl;
    }
    return defaultServerUrl;
  }

  /// Set custom sync server URL
  Future<void> setServerUrl(String url) async {
    final cleaned = url.trim();
    await settings.setKey(_syncServerUrlKey, cleaned);
  }

  /// Check if online sync is enabled and privacy policy has been accepted
  Future<bool> isOnlineSyncEnabled() async {
    final enabled = await settings.getBool(_onlineSyncEnabledKey, defaultValue: false);
    final accepted = await settings.getBool(_privacyPolicyAcceptedKey, defaultValue: false);
    return enabled && accepted;
  }

  /// Set online sync enabled status
  Future<void> setOnlineSyncEnabled(bool enabled) async {
    await settings.setBool(_onlineSyncEnabledKey, enabled);
  }

  /// Check if privacy policy was accepted
  Future<bool> isPrivacyPolicyAccepted() async {
    return await settings.getBool(_privacyPolicyAcceptedKey, defaultValue: false);
  }

  /// Set privacy policy accepted status
  Future<void> setPrivacyPolicyAccepted(bool accepted) async {
    await settings.setBool(_privacyPolicyAcceptedKey, accepted);
  }

  /// Check if friends onboarding was completed
  Future<bool> isFriendsOnboardingCompleted() async {
    return await settings.getBool(_friendsOnboardingCompletedKey, defaultValue: false);
  }

  static const String _cachedPrivacyPolicyKey = 'cached_privacy_policy_markdown';

  /// Set friends onboarding completed status
  Future<void> setFriendsOnboardingCompleted(bool completed) async {
    await settings.setBool(_friendsOnboardingCompletedKey, completed);
  }

  /// Get cached privacy policy markdown (saved from previous server fetch)
  Future<String?> getCachedPrivacyPolicy() async {
    final cached = await settings.getKey(_cachedPrivacyPolicyKey);
    return cached.isNotEmpty ? cached : null;
  }

  /// Save cached privacy policy markdown
  Future<void> saveCachedPrivacyPolicy(String markdown) async {
    await settings.setKey(_cachedPrivacyPolicyKey, markdown);
  }

  /// Fetch privacy policy markdown from sync server and cache it locally
  Future<String> fetchPrivacyPolicy({String? customServerUrl}) async {
    final serverUrl = customServerUrl ?? await getServerUrl();
    final response = await _dio.get(
      '$serverUrl/api/v1/timetable/privacy',
      options: Options(
        headers: {'Accept': 'application/json, text/markdown'},
      ),
    );

    if (response.statusCode == 200 && response.data != null) {
      String? markdown;
      if (response.data is Map && response.data['markdown'] != null) {
        markdown = response.data['markdown'].toString();
      } else if (response.data is String) {
        markdown = response.data as String;
      }
      if (markdown != null && markdown.isNotEmpty) {
        await saveCachedPrivacyPolicy(markdown);
        return markdown;
      }
    }
    throw Exception('Failed to load privacy policy from server');
  }

  /// Get or create persistent device ID
  Future<String> getDeviceId() async {
    var deviceId = await settings.getKey(_deviceIdKey);
    if (deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await settings.setKey(_deviceIdKey, deviceId);
    }
    return deviceId;
  }

  /// Get SHA-256 hashed device ID used as accessCode
  Future<String> getHashedDeviceId(String fileId) async {
    final rawId = await getDeviceId();
    final bytes = utf8.encode('$rawId:$fileId');
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ==================== CRYPTO (ChaCha20-Poly1305) ====================

  /// Generate a random 256-bit ChaCha20 key (base64Url encoded)
  Future<String> generateKey() async {
    final secretKey = await _cipher.newSecretKey();
    final bytes = await secretKey.extractBytes();
    return base64UrlEncode(bytes);
  }

  /// Encrypt string data with ChaCha20-Poly1305
  /// Returns combined base64Url string of [12-byte Nonce + 16-byte MAC + Ciphertext]
  Future<String> encryptString(String plaintext, String base64Key) async {
    final keyBytes = base64Url.decode(base64Key);
    final secretKey = SecretKey(keyBytes);
    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
    );

    final builder = BytesBuilder(copy: false);
    builder.add(secretBox.nonce);
    builder.add(secretBox.mac.bytes);
    builder.add(secretBox.cipherText);
    final combinedBytes = builder.toBytes();

    return base64UrlEncode(combinedBytes);
  }

  /// Decrypt combined base64Url payload with ChaCha20-Poly1305
  Future<String> decryptString(
    String encryptedPayload,
    String base64Key,
  ) async {
    final combined = base64Url.decode(encryptedPayload);
    if (combined.length < 28) {
      throw const FormatException('Encrypted payload too short');
    }

    final nonce = combined.sublist(0, 12);
    final macBytes = combined.sublist(12, 28);
    final cipherText = combined.sublist(28);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final keyBytes = base64Url.decode(base64Key);
    final secretKey = SecretKey(keyBytes);

    final decryptedBytes = await _cipher.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    final decrypted = utf8.decode(decryptedBytes);
    return decrypted;
  }

  // ==================== OWNER PUBLISHING & UPDATES ====================

  /// Check if user has already published their timetable online
  Future<bool> isTimetablePublished() async {
    final fileId = await settings.getKey(_publishedFileIdKey);
    return fileId.isNotEmpty;
  }

  /// Get the published file ID if available
  Future<String?> getPublishedFileId() async {
    final fileId = await settings.getKey(_publishedFileIdKey);
    return fileId.isNotEmpty ? fileId : null;
  }

  /// Publish the current user's timetable to the sync server
  Future<Map<String, dynamic>> publishTimetable({
    required models.Timetable timetable,
    String? customServerUrl,
  }) async {
    if (!await isOnlineSyncEnabled()) {
      throw StateError('Online sync is not enabled or privacy policy not accepted');
    }
    final serverUrl = customServerUrl ?? await getServerUrl();
    final fileId = const Uuid().v4();

    final examData = await settings.getMap('examTimetable');
    List<exam_models.Exam>? exams;
    if (examData.isNotEmpty) {
      try {
        final et = exam_models.ExamTimetable.fromJson(Map<String, dynamic>.from(examData));
        exams = et.exams;
      } catch (_) {}
    }

    // 1. Generate FriendTimetable for all 3 privacy levels
    final ttAllObj = FriendTimetable.fromTimetable(
      timetable,
      PrivacyLevel.fullDetails,
      exams: exams,
    );
    final ttBusyObj = FriendTimetable.fromTimetable(
      timetable,
      PrivacyLevel.busyBlocks,
    );
    final ttFreeObj = FriendTimetable.fromTimetable(
      timetable,
      PrivacyLevel.freeTimeOnly,
    );

    // 2. Generate 4 unique ChaCha20 keys (3 timetable tiers + 1 mailbox)
    final keyAll = await generateKey();
    final keyBusy = await generateKey();
    final keyFree = await generateKey();
    final mailboxKey = await generateKey();

    // 3. Encrypt each blob
    final ttAllEncrypted = await encryptString(
      jsonEncode(ttAllObj.toJson()),
      keyAll,
    );
    final ttBusyEncrypted = await encryptString(
      jsonEncode(ttBusyObj.toJson()),
      keyBusy,
    );
    final ttFreeEncrypted = await encryptString(
      jsonEncode(ttFreeObj.toJson()),
      keyFree,
    );

    // 4. POST to server
    final response = await _dio.post(
      '$serverUrl/api/v1/timetable/',
      data: {
        'fileId': fileId,
        'ttAll': ttAllEncrypted,
        'ttBusy': ttBusyEncrypted,
        'ttFree': ttFreeEncrypted,
      },
    );

    if (response.statusCode == 201 && response.data != null) {
      final data = response.data as Map<String, dynamic>;
      final fileId = data['fileId'] as String;
      final ownerAccessCode = data['ownerAccessCode'] as String;
      final inviteKeys = data['inviteKeys'] as Map<String, dynamic>;

      // 5. Store keys locally
      await settings.setKey(_publishedFileIdKey, fileId);
      await settings.setKey(_publishedOwnerCodeKey, ownerAccessCode);
      await settings.setKey(_publishedKeyAll, keyAll);
      await settings.setKey(_publishedKeyBusy, keyBusy);
      await settings.setKey(_publishedKeyFree, keyFree);
      await settings.setKey(_publishedMailboxKey, mailboxKey);
      await settings.setKey(
        _publishedInviteAll,
        inviteKeys['all'] as String? ?? '',
      );
      await settings.setKey(
        _publishedInviteBusy,
        inviteKeys['busy'] as String? ?? '',
      );
      await settings.setKey(
        _publishedInviteFree,
        inviteKeys['free'] as String? ?? '',
      );

      return {
        'success': true,
        'fileId': fileId,
        'inviteKeys': inviteKeys,
      };
    } else {
      throw Exception(
        'Failed to publish timetable: ${response.statusCode} - ${response.data}',
      );
    }
  }

  /// Update an existing online published timetable with new timetable contents
  Future<bool> updateOnlineTimetable({
    required models.Timetable timetable,
  }) async {
    if (!await isOnlineSyncEnabled()) return false;
    final fileId = await settings.getKey(_publishedFileIdKey);
    if (fileId.isEmpty) return false;

    final serverUrl = await getServerUrl();
    final ownerAccessCode = await settings.getKey(_publishedOwnerCodeKey);

    final keyAll = await settings.getKey(_publishedKeyAll);
    final keyBusy = await settings.getKey(_publishedKeyBusy);
    final keyFree = await settings.getKey(_publishedKeyFree);

    if (keyAll.isEmpty || keyBusy.isEmpty || keyFree.isEmpty) {
      // Re-publish if keys are missing
      await publishTimetable(timetable: timetable);
      return true;
    }

    final examData = await settings.getMap('examTimetable');
    List<exam_models.Exam>? exams;
    if (examData.isNotEmpty) {
      try {
        final et = exam_models.ExamTimetable.fromJson(Map<String, dynamic>.from(examData));
        exams = et.exams;
      } catch (_) {}
    }

    final ttAllObj = FriendTimetable.fromTimetable(
      timetable,
      PrivacyLevel.fullDetails,
      exams: exams,
    );
    final ttBusyObj = FriendTimetable.fromTimetable(
      timetable,
      PrivacyLevel.busyBlocks,
    );
    final ttFreeObj = FriendTimetable.fromTimetable(
      timetable,
      PrivacyLevel.freeTimeOnly,
    );

    final ttAllEncrypted = await encryptString(
      jsonEncode(ttAllObj.toJson()),
      keyAll,
    );
    final ttBusyEncrypted = await encryptString(
      jsonEncode(ttBusyObj.toJson()),
      keyBusy,
    );
    final ttFreeEncrypted = await encryptString(
      jsonEncode(ttFreeObj.toJson()),
      keyFree,
    );

    final response = await _dio.patch(
      '$serverUrl/api/v1/timetable/$fileId',
      data: {
        'accessCode': ownerAccessCode,
        'ttAll': ttAllEncrypted,
        'ttBusy': ttBusyEncrypted,
        'ttFree': ttFreeEncrypted,
      },
    );

    return response.statusCode == 200;
  }

  // ==================== QR PAYLOAD GENERATION & PARSING ====================

  /// Generate QR code payload for an online syncing timetable
  Future<String> generateOnlineSharePayload({
    required models.Timetable timetable,
    required PrivacyLevel privacyLevel,
    required String ownerName,
    String? userId,
  }) async {
    if (!await isOnlineSyncEnabled()) {
      throw StateError('Online sync is not enabled or privacy policy not accepted');
    }
    // Ensure published and updated with current timetable
    var fileId = await settings.getKey(_publishedFileIdKey);
    if (fileId.isEmpty) {
      await publishTimetable(timetable: timetable);
      fileId = await settings.getKey(_publishedFileIdKey);
    } else {
      final updated = await updateOnlineTimetable(timetable: timetable);
      if (!updated) {
        // Re-publish if server rejected or lost the file
        await publishTimetable(timetable: timetable);
        fileId = await settings.getKey(_publishedFileIdKey);
      }
    }

    final serverUrl = await getServerUrl();

    String inviteKey;
    String decryptionKey;

    switch (privacyLevel) {
      case PrivacyLevel.fullDetails:
        inviteKey = await settings.getKey(_publishedInviteAll);
        decryptionKey = await settings.getKey(_publishedKeyAll);
        break;
      case PrivacyLevel.busyBlocks:
        inviteKey = await settings.getKey(_publishedInviteBusy);
        decryptionKey = await settings.getKey(_publishedKeyBusy);
        break;
      case PrivacyLevel.freeTimeOnly:
        inviteKey = await settings.getKey(_publishedInviteFree);
        decryptionKey = await settings.getKey(_publishedKeyFree);
        break;
    }

    if (inviteKey.isEmpty || decryptionKey.isEmpty) {
      // Re-publish if keys were missing
      await publishTimetable(timetable: timetable);
      return generateOnlineSharePayload(
        timetable: timetable,
        privacyLevel: privacyLevel,
        ownerName: ownerName,
        userId: userId,
      );
    }

    final mailboxKey = await settings.getKey(_publishedMailboxKey);

    final payload = {
      'type': 'online_sync',
      'fileId': fileId,
      'inviteKey': inviteKey,
      'decryptionKey': decryptionKey,
      'serverUrl': serverUrl,
      'privacyLevel': privacyLevel.index,
      'name': ownerName,
      if (mailboxKey.isNotEmpty) 'mailboxKey': mailboxKey,
      if (userId != null && userId.isNotEmpty) 'userId': userId,
    };

    final jsonStr = jsonEncode(payload);
    final compressed = gzip.encode(utf8.encode(jsonStr));
    final base64Data = base64UrlEncode(compressed);
    return 'v2:sync:$base64Data';
  }

  /// Check whether scanned QR data is an online sync payload
  bool isOnlineSyncQR(String data) {
    return data.startsWith('v2:sync:') ||
        (data.startsWith('{') && data.contains('online_sync'));
  }

  /// Parse scanned online sync QR payload
  Map<String, dynamic> parseOnlineSyncQR(String data) {
    if (data.startsWith('v2:sync:')) {
      final base64Data = data.substring('v2:sync:'.length);
      final compressed = base64Url.decode(base64Data);
      final decompressed = gzip.decode(compressed);
      final jsonStr = utf8.decode(decompressed);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } else if (data.startsWith('{')) {
      return jsonDecode(data) as Map<String, dynamic>;
    }
    throw const FormatException('Invalid online sync QR format');
  }

  // ==================== FRIEND CLAIM & SYNC ====================

  /// Claim an invite from scanned QR data, register device ID with server,
  /// fetch timetable, decrypt, and save friend.
  Future<Friend> claimAndAddFriendFromQR(String qrData) async {
    if (!await isOnlineSyncEnabled()) {
      throw StateError('Online sync is disabled. Please accept the privacy policy to enable sync.');
    }
    final payload = parseOnlineSyncQR(qrData);

    final fileId = payload['fileId'] as String;
    final inviteKey = payload['inviteKey'] as String;
    final decryptionKey = payload['decryptionKey'] as String;
    final serverUrl = (payload['serverUrl'] as String?) ?? await getServerUrl();
    final name = (payload['name'] as String?) ?? 'Friend';
    final userId = payload['userId'] as String?;
    final privacyLevelIndex = payload['privacyLevel'] as int? ?? 2;
    final privacyLevel = PrivacyLevel.values[privacyLevelIndex.clamp(
      0,
      PrivacyLevel.values.length - 1,
    )];

    final myAccessCode = await getHashedDeviceId(fileId);

    // Encrypt our display name for the owner's mailbox (if mailboxKey present in QR)
    final mailboxKey = payload['mailboxKey'] as String?;
    String? encryptedName;
    if (mailboxKey != null && mailboxKey.isNotEmpty) {
      try {
        final myName = await settings.getKey('timetableOwner');
        final myUserId = await settings.getKey('timetableOwnerId');
        final displayName = myName.isNotEmpty ? myName : 'Unknown';

        final payloadStr = jsonEncode({
          'name': displayName,
          if (myUserId.isNotEmpty) 'userId': myUserId,
        });

        encryptedName = await encryptString(payloadStr, mailboxKey);
      } catch (_) {}
    }

    // 1. Claim invite & register access code (with optional encrypted name)
    final claimBody = <String, dynamic>{
      'inviteKey': inviteKey,
      'accessCode': myAccessCode,
    };
    if (encryptedName != null) claimBody['encryptedName'] = encryptedName;

    // Find existing friend early so we can strip credentials if 410
    final friendsService = GetIt.I<FriendsService>();
    final existingFriends = friendsService.getAllFriends(includeHidden: true);
    final matches = <Friend>[];
    for (final f in existingFriends) {
      if (f.syncFileId == fileId ||
          (userId != null && userId.isNotEmpty && f.userId == userId)) {
        matches.add(f);
      }
    }
    
    Friend? existing;
    if (matches.isNotEmpty) {
      existing = matches.firstWhere((m) => !m.isHidden, orElse: () => matches.first);
    }
    
    // Merge grantedAccessCode if any of the matches have it
    final mergedAccessCode = matches.map((m) => m.grantedAccessCode).firstWhere((code) => code != null, orElse: () => null);

    final accessResp = await _dio.post(
      '$serverUrl/api/v1/timetable/$fileId/access',
      data: claimBody,
    );

    if (accessResp.statusCode == 410 ||
        accessResp.statusCode == 401 ||
        accessResp.statusCode == 403) {
      if (existing != null) await friendsService.deleteFriend(existing.id);
      final data = accessResp.data is Map<String, dynamic>
          ? accessResp.data as Map<String, dynamic>
          : null;
      final code = data?['code'] as String?;
      final serverMsg = data?['message'] as String?;
      throw InvalidInviteKeyException(
        ownerName: name.isNotEmpty ? name : 'Friend',
        code: code,
        message: serverMsg ??
            'This invite code is invalid or has been invalidated by its owner.',
      );
    }

    if (accessResp.statusCode == 404) {
      throw TimetableNotFoundException(
        ownerName: name.isNotEmpty ? name : 'Friend',
        message: 'This timetable was not found on the server. The owner may have deleted or recreated it.',
      );
    }

    if (accessResp.statusCode != 200 && accessResp.statusCode != 201) {
      final msg = accessResp.data is Map<String, dynamic>
          ? (accessResp.data as Map<String, dynamic>)['message'] as String?
          : null;
      throw Exception(
        msg ?? 'Failed to claim invite (${accessResp.statusCode}): ${accessResp.data}',
      );
    }

    // 2. Fetch timetable with access code
    final fetchResp = await _dio.get(
      '$serverUrl/api/v1/timetable/$fileId',
      options: Options(
        headers: {'x-access-code': myAccessCode},
      ),
    );

    if (fetchResp.statusCode == 410 ||
        fetchResp.statusCode == 401 ||
        fetchResp.statusCode == 403) {
      if (existing != null) await friendsService.deleteFriend(existing.id);
      throw InvalidInviteKeyException(
        ownerName: name.isNotEmpty ? name : 'Friend',
        message: 'This invite code is invalid or has been invalidated by its owner.',
      );
    }

    if (fetchResp.statusCode == 404) {
      throw TimetableNotFoundException(
        ownerName: name.isNotEmpty ? name : 'Friend',
        message: 'This timetable was not found on the server.',
      );
    }

    if (fetchResp.statusCode != 200 || fetchResp.data == null) {
      throw Exception(
        'Failed to fetch timetable (${fetchResp.statusCode}): ${fetchResp.data}',
      );
    }

    final data = fetchResp.data as Map<String, dynamic>;
    final encryptedBlob = data['timetable'] as String;

    // 3. Decrypt timetable blob
    final decryptedJsonStr = await decryptString(
      encryptedBlob,
      decryptionKey,
    );
    final timetableJson = jsonDecode(decryptedJsonStr) as Map<String, dynamic>;
    final friendTimetable = FriendTimetable.fromJson(timetableJson);

    // 4. Create / update Friend in FriendsService
    final friend = Friend(
      id: existing?.id ?? const Uuid().v4(),
      name: existing?.name ?? name,
      privacyLevel: privacyLevel,
      timetable: friendTimetable,
      addedAt: existing?.addedAt ?? DateTime.now(),
      profilePicPath: existing?.profilePicPath,
      userId: userId ?? existing?.userId,
      isOnlineSync: true,
      syncFileId: fileId,
      syncAccessCode: myAccessCode,
      syncDecryptionKey: decryptionKey,
      syncServerUrl: serverUrl,
      lastSyncedAt: DateTime.now(),
      isHidden: false, // Ensure they are visible once a real QR is scanned
      grantedAccessCode: mergedAccessCode ?? existing?.grantedAccessCode,
    );

    await friendsService.saveFriend(friend);
    
    // Clean up duplicates
    for (final m in matches) {
      if (m.id != friend.id) {
        await friendsService.deleteFriend(m.id);
      }
    }
    
    return friend;
  }

  /// Sync a specific friend's timetable with the server.
  /// Returns true on success, false on transient failure.
  /// On 410 Gone (revoked/blocked), strips sync credentials from the friend record.
  Future<bool> syncFriend(Friend friend) async {
    if (!await isOnlineSyncEnabled()) return false;
    if (!friend.isOnlineSync ||
        friend.syncFileId == null ||
        friend.syncAccessCode == null ||
        friend.syncDecryptionKey == null) {
      return false;
    }

    try {
      final serverUrl = friend.syncServerUrl ?? await getServerUrl();
      final response = await _dio.get(
        '$serverUrl/api/v1/timetable/${friend.syncFileId}',
        options: Options(
          headers: {'x-access-code': friend.syncAccessCode},
        ),
      );

      if (response.statusCode == 410) {
        // Access revoked or device blocked — remove the friend
        await GetIt.I<FriendsService>().deleteFriend(friend.id);
        return false;
      }

      if (response.statusCode != 200 || response.data == null) {
        return false;
      }

      final data = response.data as Map<String, dynamic>;
      final encryptedBlob = data['timetable'] as String;

      final decryptedJsonStr = await decryptString(
        encryptedBlob,
        friend.syncDecryptionKey!,
      );
      final timetableJson =
          jsonDecode(decryptedJsonStr) as Map<String, dynamic>;
      final newTimetable = FriendTimetable.fromJson(timetableJson);

      final updatedFriend = friend.copyWith(
        timetable: newTimetable,
        lastSyncedAt: DateTime.now(),
      );

      final friendsService = GetIt.I<FriendsService>();
      await friendsService.saveFriend(updatedFriend);
      return true;
    } catch (_) {
      return false;
    }
  }
  /// Sync all online-enabled friends using bulk batch requests when possible
  Future<int> syncAllFriends() async {
    if (!await isOnlineSyncEnabled()) return 0;
    final friendsService = GetIt.I<FriendsService>();
    final friends = friendsService.getAllFriends(includeHidden: true);
    final onlineFriends = friends.where((f) =>
        f.isOnlineSync &&
        f.syncFileId != null &&
        f.syncAccessCode != null &&
        f.syncDecryptionKey != null).toList();

    if (onlineFriends.isEmpty) {
      return 0;
    }

    final defaultServerUrl = await getServerUrl();
    // Group friends by server URL
    final serverGroups = <String, List<Friend>>{};
    for (final friend in onlineFriends) {
      final url = friend.syncServerUrl ?? defaultServerUrl;
      serverGroups.putIfAbsent(url, () => []).add(friend);
    }

    var successCount = 0;

    for (final entry in serverGroups.entries) {
      final serverUrl = entry.key;
      final groupFriends = entry.value;

      try {
        final itemsPayload = groupFriends
            .map((f) => {'fileId': f.syncFileId, 'accessCode': f.syncAccessCode})
            .toList();

        final response = await _dio.post(
          '$serverUrl/api/v1/timetable/bulk',
          data: {'items': itemsPayload},
          options: Options(
            headers: {'Content-Type': 'application/json'},
          ),
        );

        if (response.statusCode == 200 && response.data != null) {
          final data = response.data as Map<String, dynamic>;
          final results = data['results'] as List<dynamic>? ?? [];
          final resultsByFileId = <String, Map<String, dynamic>>{};
          for (final res in results) {
            if (res is Map<String, dynamic> && res['fileId'] != null) {
              resultsByFileId[res['fileId'] as String] = res;
            }
          }

          for (final friend in groupFriends) {
            final res = resultsByFileId[friend.syncFileId];
            if (res == null) continue;

            // 410 Gone: access revoked or device blocked
            if (res['gone'] == true) {
              await friendsService.deleteFriend(friend.id);
              continue;
            }

            if (res['success'] == true && res['timetable'] is String) {
              try {
                final encryptedBlob = res['timetable'] as String;
                final decryptedJsonStr = await decryptString(
                  encryptedBlob,
                  friend.syncDecryptionKey!,
                );
                final timetableJson =
                    jsonDecode(decryptedJsonStr) as Map<String, dynamic>;
                final newTimetable = FriendTimetable.fromJson(timetableJson);

                final updatedFriend = friend.copyWith(
                  timetable: newTimetable,
                  lastSyncedAt: DateTime.now(),
                );
                await friendsService.saveFriend(updatedFriend);
                successCount++;
              } catch (_) {}
            }
          }
          continue;
        }
      } catch (_) {
        // Fallback to individual sync if bulk endpoint fails
      }

      // Fallback: sync individually
      for (final friend in groupFriends) {
        final success = await syncFriend(friend);
        if (success) successCount++;
      }
    }

    return successCount;
  }

  // ==================== OWNER: MAILBOX & ACCESS MANAGEMENT ====================

  /// Fetch pending mailbox entries, decrypt names, then clear mailbox on server.
  /// Returns a list of [MailboxEntry] with decrypted names.
  Future<List<MailboxEntry>> checkAndSyncMailbox() async {
    if (!await isOnlineSyncEnabled()) return [];
    final fileId = await settings.getKey(_publishedFileIdKey);
    if (fileId.isEmpty) return [];

    final mailboxKey = await settings.getKey(_publishedMailboxKey);
    if (mailboxKey.isEmpty) return [];

    final serverUrl = await getServerUrl();
    final ownerCode = await settings.getKey(_publishedOwnerCodeKey);

    final response = await _dio.get(
      '$serverUrl/api/v1/timetable/$fileId/mailbox',
      options: Options(headers: {'x-access-code': ownerCode}),
    );

    if (response.statusCode != 200 || response.data == null) return [];

    final data = response.data as Map<String, dynamic>;
    final entries = data['entries'] as List<dynamic>? ?? [];

    final result = <MailboxEntry>[];
    for (final e in entries) {
      if (e is! Map<String, dynamic>) continue;
      try {
        final encryptedName = e['encryptedName'] as String;
        final decryptedStr = await decryptString(encryptedName, mailboxKey);
        String name = decryptedStr;
        String? userId;
        
        try {
          if (decryptedStr.trim().startsWith('{')) {
            final json = jsonDecode(decryptedStr) as Map<String, dynamic>;
            name = json['name'] as String? ?? 'Unknown';
            userId = json['userId'] as String?;
          }
        } catch (_) {}

        result.add(MailboxEntry(
          accessCode: e['accessCode'] as String,
          name: name,
          userId: userId,
          permissionLevel: e['permissionLevel'] as String? ?? 'unknown',
          createdAt: DateTime.tryParse(e['createdAt'] as String? ?? '') ?? DateTime.now(),
        ));
      } catch (_) {}
    }

    // Clear mailbox from server after successfully reading
    if (result.isNotEmpty) {
      try {
        await _dio.delete(
          '$serverUrl/api/v1/timetable/$fileId/mailbox',
          options: Options(headers: {'x-access-code': ownerCode}),
        );
        
        // Save to local friends so they aren't lost
        final friendsService = GetIt.I<FriendsService>();
        final friends = friendsService.getAllFriends(includeHidden: true);
        
        for (final entry in result) {
          Friend? match;
          if (entry.userId != null) {
            match = friends.where((f) => f.userId == entry.userId).firstOrNull;
          }
          match ??= friends.where((f) => f.grantedAccessCode == entry.accessCode || f.syncAccessCode == entry.accessCode).firstOrNull;
          
          if (match != null) {
            if (match.grantedAccessCode != entry.accessCode) {
              await friendsService.saveFriend(match.copyWith(grantedAccessCode: entry.accessCode));
            }
          } else {
            final stub = Friend(
              id: const Uuid().v4(),
              name: entry.name,
              privacyLevel: PrivacyLevel.freeTimeOnly,
              timetable: FriendTimetable(days: []),
              addedAt: DateTime.now(),
              userId: entry.userId,
              syncAccessCode: null, // this is for their timetable, not ours
              grantedAccessCode: entry.accessCode,
              isHidden: true,
            );
            await friendsService.saveFriend(stub);
          }
        }
      } catch (_) {}
    }

    return result;
  }

  /// Fetch the access list (active + blocked) from the server.
  Future<TimetableAccessInfo> fetchAccessList() async {
    if (!await isOnlineSyncEnabled()) {
      return const TimetableAccessInfo(active: [], blocked: []);
    }
    final fileId = await settings.getKey(_publishedFileIdKey);
    if (fileId.isEmpty) {
      return const TimetableAccessInfo(active: [], blocked: []);
    }

    final serverUrl = await getServerUrl();
    final ownerCode = await settings.getKey(_publishedOwnerCodeKey);

    final response = await _dio.get(
      '$serverUrl/api/v1/timetable/$fileId/access-list',
      options: Options(headers: {'x-access-code': ownerCode}),
    );

    if (response.statusCode != 200 || response.data == null) {
      return const TimetableAccessInfo(active: [], blocked: []);
    }

    final data = response.data as Map<String, dynamic>;
    final activeJson = data['active'] as List<dynamic>? ?? [];
    final blockedJson = data['blocked'] as List<dynamic>? ?? [];

    return TimetableAccessInfo(
      active: activeJson.map((e) {
        final m = e as Map<String, dynamic>;
        return ActiveAccessEntry(
          accessCode: m['accessCode'] as String,
          permissionLevel: m['permissionLevel'] as String? ?? 'unknown',
          hasEncryptedName: m['hasEncryptedName'] as bool? ?? false,
          createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
        );
      }).toList(),
      blocked: blockedJson.map((e) {
        final m = e as Map<String, dynamic>;
        return BlockedAccessEntry(
          accessCode: m['accessCode'] as String,
          hasEncryptedName: m['hasEncryptedName'] as bool? ?? false,
          createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
        );
      }).toList(),
    );
  }

  /// Remove a device's access code from the timetable (immediate revocation).
  Future<void> removeDeviceAccess(String targetAccessCode) async {
    if (!await isOnlineSyncEnabled()) return;
    final fileId = await settings.getKey(_publishedFileIdKey);
    if (fileId.isEmpty) return;
    final serverUrl = await getServerUrl();
    final ownerCode = await settings.getKey(_publishedOwnerCodeKey);
    await _dio.delete(
      '$serverUrl/api/v1/timetable/$fileId/access/$targetAccessCode',
      options: Options(headers: {'x-access-code': ownerCode}),
    );
  }

  /// Block a device permanently (gravestone). They can't re-register until unblocked.
  Future<void> blockDevice(String targetAccessCode) async {
    if (!await isOnlineSyncEnabled()) return;
    final fileId = await settings.getKey(_publishedFileIdKey);
    if (fileId.isEmpty) return;
    final serverUrl = await getServerUrl();
    final ownerCode = await settings.getKey(_publishedOwnerCodeKey);
    await _dio.post(
      '$serverUrl/api/v1/timetable/$fileId/access/$targetAccessCode/block',
      options: Options(headers: {'x-access-code': ownerCode}),
    );
  }

  /// Unblock a previously blocked device.
  Future<void> unblockDevice(String targetAccessCode) async {
    if (!await isOnlineSyncEnabled()) return;
    final fileId = await settings.getKey(_publishedFileIdKey);
    if (fileId.isEmpty) return;
    final serverUrl = await getServerUrl();
    final ownerCode = await settings.getKey(_publishedOwnerCodeKey);
    await _dio.delete(
      '$serverUrl/api/v1/timetable/$fileId/access/$targetAccessCode/block',
      options: Options(headers: {'x-access-code': ownerCode}),
    );
  }

  /// Regenerate all invite keys for the user's published timetable.
  /// Old invite keys / QR codes will no longer work for new pairings,
  /// but existing connected devices retain their access.
  Future<Map<String, String>> regenerateInviteKeys() async {
    if (!await isOnlineSyncEnabled()) {
      throw StateError('Online sync is not enabled');
    }
    final fileId = await settings.getKey(_publishedFileIdKey);
    if (fileId.isEmpty) {
      throw Exception('No published timetable found. Share your timetable first.');
    }
    final serverUrl = await getServerUrl();
    final ownerCode = await settings.getKey(_publishedOwnerCodeKey);
    if (ownerCode.isEmpty) {
      throw Exception('Missing owner access code.');
    }

    final response = await _dio.post(
      '$serverUrl/api/v1/timetable/$fileId/invite-keys/regenerate',
      options: Options(headers: {'x-access-code': ownerCode}),
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data as Map<String, dynamic>;
      final inviteKeys = data['inviteKeys'] as Map<String, dynamic>;

      final allKey = inviteKeys['all'] as String? ?? '';
      final busyKey = inviteKeys['busy'] as String? ?? '';
      final freeKey = inviteKeys['free'] as String? ?? '';

      await settings.setKey(_publishedInviteAll, allKey);
      await settings.setKey(_publishedInviteBusy, busyKey);
      await settings.setKey(_publishedInviteFree, freeKey);

      return {
        'all': allKey,
        'busy': busyKey,
        'free': freeKey,
      };
    } else {
      throw Exception(
        'Failed to regenerate invite keys: ${response.statusCode} - ${response.data}',
      );
    }
  }

  /// Delete the published timetable entirely from the server, clear local publish credentials,
  /// and opt out of online sync (disabling sync and resetting consent).
  Future<void> deletePublishedTimetable() async {
    final fileId = await settings.getKey(_publishedFileIdKey);
    final ownerCode = await settings.getKey(_publishedOwnerCodeKey);
    final serverUrl = await getServerUrl();

    try {
      if (fileId.isNotEmpty && ownerCode.isNotEmpty) {
        try {
          await _dio.delete(
            '$serverUrl/api/v1/timetable/$fileId',
            options: Options(
              headers: {'x-access-code': ownerCode},
            ),
          );
        } catch (_) {
          // Ignore network or missing file errors during deletion
        }
      }
    } finally {
      // Always clear local published credentials
      await clearPublishedTimetableCredentials();

      // Completely remove any online timetables from other people
      if (GetIt.I.isRegistered<FriendsService>()) {
        final friendsService = GetIt.I<FriendsService>();
        final allFriends = friendsService.getAllFriends(includeHidden: true);
        for (final friend in allFriends) {
          if (friend.isOnlineSync ||
              (friend.syncFileId != null && friend.syncFileId!.isNotEmpty)) {
            await friendsService.deleteFriend(friend.id);
          }
        }
      }

      // Opt out of online sync and reset policy consent
      await setOnlineSyncEnabled(false);
      await setPrivacyPolicyAccepted(false);
    }
  }

  /// Clears all local published timetable credentials from settings.
  Future<void> clearPublishedTimetableCredentials() async {
    await settings.removeKey(_publishedFileIdKey);
    await settings.removeKey(_publishedOwnerCodeKey);
    await settings.removeKey(_publishedKeyAll);
    await settings.removeKey(_publishedKeyBusy);
    await settings.removeKey(_publishedKeyFree);
    await settings.removeKey(_publishedInviteAll);
    await settings.removeKey(_publishedInviteBusy);
    await settings.removeKey(_publishedInviteFree);
    await settings.removeKey(_publishedMailboxKey);
  }
}

/// Data class representing a single entry decrypted from the mailbox.
class MailboxEntry {
  final String accessCode;
  final String name;
  final String? userId;
  final String permissionLevel;
  final DateTime createdAt;

  const MailboxEntry({
    required this.accessCode,
    required this.name,
    this.userId,
    required this.permissionLevel,
    required this.createdAt,
  });
}

/// Data class representing the full access list for a timetable.
class TimetableAccessInfo {
  final List<ActiveAccessEntry> active;
  final List<BlockedAccessEntry> blocked;

  const TimetableAccessInfo({required this.active, required this.blocked});
}

class ActiveAccessEntry {
  final String accessCode;
  final String permissionLevel;
  final bool hasEncryptedName;
  final DateTime createdAt;
  /// Decrypted name from mailbox (populated locally).
  final String? name;
  /// Decrypted userId from mailbox (populated locally).
  final String? userId;

  const ActiveAccessEntry({
    required this.accessCode,
    required this.permissionLevel,
    required this.hasEncryptedName,
    required this.createdAt,
    this.name,
    this.userId,
  });
}

class BlockedAccessEntry {
  final String accessCode;
  final bool hasEncryptedName;
  final DateTime createdAt;
  /// Decrypted name from mailbox (populated locally).
  final String? name;
  /// Decrypted userId from mailbox (populated locally).
  final String? userId;

  const BlockedAccessEntry({
    required this.accessCode,
    this.hasEncryptedName = false,
    required this.createdAt,
    this.name,
    this.userId,
  });
}

/// Exception thrown when an invite key has expired or been regenerated.
class InvalidInviteKeyException implements Exception {
  final String ownerName;
  final String? code;
  final String message;

  const InvalidInviteKeyException({
    required this.ownerName,
    this.code,
    this.message = 'This invite code is invalid or has been regenerated by its owner.',
  });

  @override
  String toString() => message;
}

/// Exception thrown when a timetable is not found on the server.
class TimetableNotFoundException implements Exception {
  final String ownerName;
  final String message;

  const TimetableNotFoundException({
    required this.ownerName,
    this.message = 'This schedule was not found on the server.',
  });

  @override
  String toString() => message;
}
