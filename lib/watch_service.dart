import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nscgschedule/settings.dart';
import 'package:nscgschedule/requests.dart';

/// Service to handle communication with WearOS companion app
class WatchService {
  static final WatchService _instance = WatchService._internal();
  static WatchService get instance => _instance;

  WatchService._internal();

  static const MethodChannel _channel = MethodChannel(
    'uk.bw86.nscgschedule/watch',
  );
  bool _isInitialized = false;

  /// Initialize the watch service
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      _isInitialized = true;
      debugPrint('WatchService: Initialized');
    } catch (e) {
      debugPrint('WatchService: Failed to initialize - $e');
    }
  }

  /// Dispose of resources
  void dispose() {
    _isInitialized = false;
  }

  /// Check if a watch is paired and connected
  Future<bool> get isWatchConnected async {
    try {
      final result = await _channel.invokeMethod<bool>('isConnected');
      return result ?? false;
    } catch (e) {
      debugPrint('WatchService: Error checking connection - $e');
      return false;
    }
  }

  /// Send data to watch using native Data Layer API
  Future<void> _sendDataToWatch(Map<String, dynamic> data) async {
    try {
      // Convert to JSON string for safe transport
      final jsonString = jsonEncode(data);

      await _channel.invokeMethod('sendData', {
        'path': '/watch_data',
        'data': jsonString,
      });

      debugPrint('WatchService: Sent data to watch');
    } catch (e) {
      debugPrint('WatchService: Error sending data - $e');
    }
  }

  /// Update the watch with new timetable data
  /// Call this when the timetable is updated
  ///
  /// When [forceRefresh] is true, will attempt to fetch fresh data from server
  /// even if not logged in (useful for watch-initiated refresh requests)
  Future<void> syncTimetable({bool forceRefresh = false}) async {
    try {
      final loggedin = await settings.getBool('loggedin');

      Map<String, dynamic> timetableData = {};
      String? timetableUpdated;

      // Always attempt to fetch if logged in, or if force refresh is requested
      if (loggedin || forceRefresh) {
        try {
          final fetched = await NSCGRequests.instance.getTimeTable(
            notifyWatch: false,
          );
          if (fetched != null) {
            timetableData = fetched.toJson();
            timetableUpdated = await settings.getKey('timetableUpdated');
          }
        } catch (e) {
          // ignore and fall back to stored data
          debugPrint('WatchService: Failed to fetch fresh timetable - $e');
        }
      }

      // If we don't have fetched data, use stored data
      if (timetableData.isEmpty) {
        timetableData = await settings.getMap('timetable');
        timetableUpdated = await settings.getKey('timetableUpdated');
      }

      if (timetableData.isNotEmpty) {
        await _sendDataToWatch({
          'timetable': timetableData,
          'timetableUpdated': timetableUpdated,
          'lastSync': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('WatchService: Error syncing timetable - $e');
    }
  }

  /// Update the watch with new exam timetable data
  /// Call this when the exam timetable is updated
  ///
  /// When [forceRefresh] is true, will attempt to fetch fresh data from server
  /// even if not logged in (useful for watch-initiated refresh requests)
  Future<void> syncExamTimetable({bool forceRefresh = false}) async {
    try {
      final loggedin = await settings.getBool('loggedin');

      Map<String, dynamic> examData = {};
      String? examUpdated;

      final isDebug = await settings.getBool('debugMode', defaultValue: false);

      // Always attempt to fetch if logged in (and not debugMode), or if force refresh is requested
      if ((loggedin && !isDebug) || forceRefresh) {
        try {
          final fetched = await NSCGRequests.instance.getExamTimetable(
            notifyWatch: false,
          );
          if (fetched != null) {
            examData = fetched.toJson();
            examUpdated = await settings.getKey('examTimetableUpdated');
          }
        } catch (e) {
          // ignore and fall back to stored data
          debugPrint('WatchService: Failed to fetch fresh exam timetable - $e');
        }
      }

      // If no fetched data available, use stored data
      if (examData.isEmpty) {
        examData = await settings.getMap('examTimetable');
        examUpdated = await settings.getKey('examTimetableUpdated');
      }

      if (examData.isNotEmpty) {
        await _sendDataToWatch({
          'examTimetable': examData,
          'examUpdated': examUpdated,
          'lastSync': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('WatchService: Error syncing exam timetable - $e');
    }
  }

  /// Update the application context with current data
  /// This persists the data even when the app is not running
  Future<void> updateContext() async {
    try {
      final timetableData = await settings.getMap('timetable');
      final examData = await settings.getMap('examTimetable');
      final timetableUpdated = await settings.getKey('timetableUpdated');
      final examUpdated = await settings.getKey('examTimetableUpdated');

      await _sendDataToWatch({
        'timetable': timetableData,
        'examTimetable': examData,
        'timetableUpdated': timetableUpdated,
        'examUpdated': examUpdated,
        'lastSync': DateTime.now().toIso8601String(),
      });

      debugPrint('WatchService: Updated application context');
    } catch (e) {
      debugPrint('WatchService: Error updating context - $e');
    }
  }
}
