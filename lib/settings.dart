import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final Settings settings = GetIt.I<Settings>();

class Settings {
  static const String _darkModeKey = 'darkMode';
  static const String _useSystemThemeKey = 'useSystemTheme';
  static const String _useMaterialYouKey = 'useMaterialYou';
  static const String _notificationsEnabledKey = 'notificationsEnabled';
  static const String _notifyMinutesBeforeKey = 'notifyMinutesBefore';
  static const String _notifyMinutesBeforeEnabledKey =
      'notifyMinutesBeforeEnabled';
  static const String _notifyOnStartTimeKey = 'notifyOnStartTime';
  static const String _dynamicFriendHeaderColorKey = 'dynamicFriendHeaderColor';

  late final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  Box? _secureBox;
  bool _secureBoxInitialized = false;

  static const _hiveEncryptionKeyName = 'hive_encryption_key';
  final _themeChangeController = StreamController<bool>.broadcast();
  final _notificationSettingsChangeController =
      StreamController<void>.broadcast();

  Stream<bool> get onThemeChanged => _themeChangeController.stream;
  Stream<void> get onNotificationSettingsChanged =>
      _notificationSettingsChangeController.stream;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<Box> _getBox() async {
    final dir = await getApplicationSupportDirectory();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.init(dir.path);
    }
    return await Hive.openBox('settings');
  }

  Future<Uint8List> _getOrCreateEncryptionKey() async {
    try {
      final existing = await _secureStorage.read(key: _hiveEncryptionKeyName);
      if (existing != null && existing.isNotEmpty) {
        return base64Url.decode(existing);
      }
    } catch (_) {
      // ignore and generate new
    }

    final key = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final encoded = base64UrlEncode(key);
    await _secureStorage.write(key: _hiveEncryptionKeyName, value: encoded);
    return Uint8List.fromList(key);
  }

  Future<Box> _getSecureBox() async {
    if (_secureBoxInitialized && _secureBox != null) return _secureBox!;
    final dir = await getApplicationSupportDirectory();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.init(dir.path);
    }
    final key = await _getOrCreateEncryptionKey();
    _secureBox = await Hive.openBox(
      'secure_settings',
      encryptionCipher: HiveAesCipher(key),
    );
    _secureBoxInitialized = true;
    return _secureBox!;
  }

  Future<void> setKey(String key, String value) async {
    final box = await _getBox();
    await box.put(key, value);
  }

  Future<String> getKey(String key) async {
    final box = await _getBox();
    return box.get(key, defaultValue: '');
  }

  Future<T> getEnum<T>(String key, {T? defaultValue}) async {
    final box = await _getBox();
    return box.get(key, defaultValue: defaultValue);
  }

  Future<void> setEnum<T>(String key, T value) async {
    final box = await _getBox();
    await box.put(key, value);
  }

  Future<void> removeKey(String key) async {
    final box = await _getBox();
    await box.delete(key);
  }

  Future<void> setDynamic(String key, dynamic value) async {
    final box = await _getBox();
    await box.put(key, value);
  }

  Future<dynamic> getDynamic(String key, {dynamic defaultValue}) async {
    final box = await _getBox();
    return box.get(key, defaultValue: defaultValue);
  }

  Future<void> setMap(String key, Map<String, dynamic> value) async {
    // Use encrypted storage for sensitive timetable data
    if (key == 'timetable' || key == 'examTimetable') {
      final box = await _getSecureBox();
      await box.put(key, value);
    } else {
      final box = await _getBox();
      await box.put(key, value);
    }
  }

  Future<Map<String, dynamic>> getMap(
    String key, {
    Map<String, dynamic>? defaultValue,
  }) async {
    try {
      final box = (key == 'timetable' || key == 'examTimetable')
          ? await _getSecureBox()
          : await _getBox();
      final value = box.get(key, defaultValue: defaultValue ?? {});
      if (value is Map) {
        // Convert all keys to String and handle nested maps
        return value.map(
          (k, v) => MapEntry(
            k.toString(),
            v is Map ? Map<String, dynamic>.from(v) : v,
          ),
        );
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  Future<void> setBool(String key, bool value) async {
    final box = await _getBox();
    await box.put(key, value);
    if (key == _darkModeKey ||
        key == _useSystemThemeKey ||
        key == _useMaterialYouKey) {
      _themeChangeController.add(true);
    }
  }

  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final box = await _getBox();
    return box.get(key, defaultValue: defaultValue) as bool;
  }

  // Theme specific methods
  Future<bool> getDarkMode() async {
    return _prefs.getBool(_darkModeKey) ?? false;
  }

  Future<void> setDarkMode(bool value) async {
    await _prefs.setBool(_darkModeKey, value);
    _themeChangeController.add(!(await getUseSystemTheme()) && value);
  }

  Future<bool> getUseSystemTheme() async {
    return _prefs.getBool(_useSystemThemeKey) ??
        true; // Default to true for system theme
  }

  Future<void> setUseSystemTheme(bool value) async {
    await _prefs.setBool(_useSystemThemeKey, value);
    _themeChangeController.add(true);
  }

  // Material You preference
  Future<bool> getUseMaterialYou() async {
    // First check Hive, then fall back to SharedPreferences
    final box = await _getBox();
    final fromBox = box.get(_useMaterialYouKey) as bool?;
    if (fromBox != null) {
      return fromBox;
    }
    // If not in Hive, get from SharedPreferences and sync to Hive
    final value = _prefs.getBool(_useMaterialYouKey) ?? true;
    await box.put(_useMaterialYouKey, value);
    return value;
  }

  Future<void> setUseMaterialYou(bool value) async {
    await _prefs.setBool(_useMaterialYouKey, value);
    _themeChangeController.add(true);
    // Also update the value in Hive for consistency
    final box = await _getBox();
    await box.put(_useMaterialYouKey, value);
  }

  // Dynamic friend header color preference
  Future<bool> getDynamicFriendHeaderColor() async {
    return getBool(_dynamicFriendHeaderColorKey, defaultValue: false);
  }

  Future<void> setDynamicFriendHeaderColor(bool value) async {
    await setBool(_dynamicFriendHeaderColorKey, value);
    _themeChangeController.add(true); // Optional: trigger theme update
  }

  // Notification settings
  Future<bool> getNotificationsEnabled() async {
    return getBool(_notificationsEnabledKey, defaultValue: true);
  }

  Future<void> setNotificationsEnabled(bool value) async {
    await setBool(_notificationsEnabledKey, value);
    _notificationSettingsChangeController.add(null);
  }

  Future<int> getNotifyMinutesBefore() async {
    final box = await _getBox();
    return box.get(_notifyMinutesBeforeKey, defaultValue: 5) as int;
  }

  Future<void> setNotifyMinutesBefore(int value) async {
    final box = await _getBox();
    await box.put(_notifyMinutesBeforeKey, value);
    _notificationSettingsChangeController.add(null);
  }

  Future<bool> getNotifyMinutesBeforeEnabled() async {
    return getBool(_notifyMinutesBeforeEnabledKey, defaultValue: true);
  }

  Future<void> setNotifyMinutesBeforeEnabled(bool value) async {
    await setBool(_notifyMinutesBeforeEnabledKey, value);
    _notificationSettingsChangeController.add(null);
  }

  Future<bool> getNotifyOnStartTime() async {
    return getBool(_notifyOnStartTimeKey, defaultValue: true);
  }

  Future<void> setNotifyOnStartTime(bool value) async {
    await setBool(_notifyOnStartTimeKey, value);
    _notificationSettingsChangeController.add(null);
  }

  Future<bool> toggleBool(String key) async {
    final box = await _getBox();
    await box.put(key, !box.get(key, defaultValue: false));
    return box.get(key, defaultValue: false);
  }

  Future<void> removeBool(String key) async {
    final box = await _getBox();
    await box.delete(key);
  }

  Future<bool> containsKey(String key) async {
    final box = await _getBox();
    return box.containsKey(key);
  }
}
