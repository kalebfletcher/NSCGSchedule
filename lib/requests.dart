import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:nscgschedule/models/timetable_models.dart';
import 'package:nscgschedule/models/exam_models.dart';
import 'package:nscgschedule/settings.dart';
import 'package:nscgschedule/watch_service.dart';
import 'package:nscgschedule/widget_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:nscgschedule/updater.dart';

class NSCGRequests {
  final Dio _dio = Dio();
  static final instance = NSCGRequests();
  StreamController<bool> updateController = StreamController<bool>.broadcast();
  StreamController<bool> debugModeController =
      StreamController<bool>.broadcast();
  StreamController<bool> loggedinController =
      StreamController<bool>.broadcast();

  NSCGRequests() {
    _dio.options.baseUrl = 'https://my.nulc.ac.uk';
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);

    // Configure SSL certificate handling for self-signed or problematic certificates
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
            // Only bypass SSL verification for my.nulc.ac.uk
            return host == 'my.nulc.ac.uk';
          };
      return client;
    };
  }

  Future<bool> debugMode(bool value) async {
    await settings.setBool('debugMode', value);
    debugModeController.add(value);
    return value;
  }

  Future<Timetable?> getTimeTable({bool notifyWatch = true}) async {
    try {
      final cookiesString = await settings.getKey('cookies');
      if (cookiesString.isEmpty) {
        return null;
      }

      // Parse the cookies string and format it for the Cookie header
      final cookiePairs = <String>[];
      final cookieMatches = RegExp(
        r'name: ([^,]+),.*?value: ([^,}]+)',
      ).allMatches(cookiesString);

      for (final match in cookieMatches) {
        if (match.groupCount >= 2) {
          final name = match.group(1)?.trim();
          final value = match.group(2)?.trim();
          if (name != null && value != null) {
            cookiePairs.add('$name=$value');
          }
        }
      }

      final cookieHeader = cookiePairs.join('; ');

      final response = await _dio.get<String>(
        '/studentTT/',
        options: Options(
          headers: {'Cookie': cookieHeader, 'Accept': 'text/html'},
          responseType: ResponseType.plain,
        ),
      );

      if (response.statusCode == 200 &&
          response.data != null &&
          response.realUri.toString().contains('studentTT/')) {
        Timetable timetable = Timetable.fromHtml(response.data!);
        // Try to extract the owner's name from the HTML and save it
        final owner = Timetable.extractOwnerName(response.data!);
        if (owner != null && owner.isNotEmpty) {
          final normalized = owner.replaceAll(RegExp(r'\s+'), ' ').trim();
          await settings.setKey('timetableOwner', normalized);
        }

        // Also fetch the main homepage to extract a stable username/refNo
        try {
          final homeResp = await _dio.get<String>(
            '/',
            options: Options(
              headers: {'Cookie': cookieHeader, 'Accept': 'text/html'},
              responseType: ResponseType.plain,
            ),
          );
          if (homeResp.statusCode == 200 && homeResp.data != null) {
            final homeHtml = homeResp.data!;
            // Look for patterns like "[refNo] => 123456" and "[username] => C123456"
            final refMatch = RegExp(
              r"\[refNo\]\s*=>\s*([0-9]+)",
            ).firstMatch(homeHtml);
            final userMatch = RegExp(
              r"\[username\]\s*=>\s*([A-Za-z0-9_@.-]+)",
            ).firstMatch(homeHtml);
            if (refMatch != null) {
              await settings.setKey(
                'timetableOwnerRef',
                refMatch.group(1) ?? '',
              );
            }
            if (userMatch != null) {
              await settings.setKey(
                'timetableOwnerId',
                userMatch.group(1) ?? '',
              );
            }
          }
        } catch (e) {
          // ignore homepage parse failures
        }

        await settings.setMap('timetable', timetable.toJson());
        await settings.setKey(
          'timetableUpdated',
          DateTime.now().toIso8601String(),
        );
        // Sync with WearOS watch unless caller requested suppression
        if (notifyWatch) {
          await WatchService.instance.syncTimetable();
          await WatchService.instance.updateContext();
        }
        // Sync to home screen widgets
        await WidgetService.instance.syncTimetableToWidget();
        return timetable;
      } else {
        settings.setBool('loggedin', false);
        loggedinController.add(false);
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  Future<ExamTimetable?> getExamTimetable({bool notifyWatch = true}) async {
    try {
      final cookiesString = await settings.getKey('cookies');
      if (cookiesString.isEmpty) {
        return null;
      }

      // Parse the cookies string and format it for the Cookie header
      final cookiePairs = <String>[];
      final cookieMatches = RegExp(
        r'name: ([^,]+),.*?value: ([^,}]+)',
      ).allMatches(cookiesString);

      for (final match in cookieMatches) {
        if (match.groupCount >= 2) {
          final name = match.group(1)?.trim();
          final value = match.group(2)?.trim();
          if (name != null && value != null) {
            cookiePairs.add('$name=$value');
          }
        }
      }

      final cookieHeader = cookiePairs.join('; ');

      final response = await _dio.get<String>(
        '/exams/',
        options: Options(
          headers: {'Cookie': cookieHeader, 'Accept': 'text/html'},
          responseType: ResponseType.plain,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        ExamTimetable examTimetable = ExamTimetable.fromHtml(response.data!);
        await settings.setMap('examTimetable', examTimetable.toJson());
        await settings.setKey(
          'examTimetableUpdated',
          DateTime.now().toIso8601String(),
        );
        // Sync with WearOS watch unless caller requested suppression
        if (notifyWatch) {
          await WatchService.instance.syncExamTimetable();
          await WatchService.instance.updateContext();
        }
        // Sync to home screen widgets
        await WidgetService.instance.syncExamTimetableToWidget();
        return examTimetable;
      } else {
        settings.setBool('loggedin', false);
        loggedinController.add(false);
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>> updateApp() async {
    try {
      final latest = await NSCGScheduleLatest.fetch();
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version.contains('-')
          ? packageInfo.version.split('-')[0]
          : packageInfo.version;
      if (latest.version != currentVersion) {
        updateController.add(true);
      } else {
        updateController.add(false);
      }
      return {
        'version': latest.version,
        'changelog': latest.changelog,
        'downloads': latest.downloads
            .map((d) => {'name': d.name, 'url': d.directUrl})
            .toList(),
      };
    } catch (e) {
      return {};
    }
  }
}
