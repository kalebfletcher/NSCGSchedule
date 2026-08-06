import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
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

  /// Process redirect URL containing authToken JWT parameter
  Future<Map<String, String>> processAuthUrl(String url) async {
    final result = <String, String>{};
    try {
      final uri = Uri.tryParse(url);
      final authToken = uri?.queryParameters['authToken'];
      if (authToken == null || authToken.isEmpty) return result;

      final parts = authToken.split('.');
      if (parts.length < 2) return result;

      final normalized = base64Url.normalize(parts[1]);
      final decodedJson = utf8.decode(base64Url.decode(normalized));
      final payload = jsonDecode(decodedJson);

      if (payload is Map<String, dynamic>) {
        final upn = (payload['upn'] ?? payload['email'] ?? payload['unique_name'] ?? '').toString().trim();
        if (upn.isNotEmpty) {
          final username = upn.contains('@') ? upn.split('@').first : upn;
          final digits = username.replaceAll(RegExp(r'[^0-9]'), '');
          if (username.isNotEmpty) {
            await settings.setKey('timetableOwnerId', username);
            result['username'] = username;
          }
          if (digits.isNotEmpty) {
            await settings.setKey('timetableOwnerRef', digits);
            result['ref'] = digits;
          }
        }

        final name = (payload['name'] ?? payload['given_name'] ?? payload['displayName'] ?? payload['commonname'] ?? '').toString().trim();
        if (name.isNotEmpty) {
          await settings.setKey('timetableOwner', name);
          result['name'] = name;
        }
      }
    } catch (_) {}
    return result;
  }

  Future<bool> debugMode(bool value) async {
    await settings.setBool('debugMode', value);
    debugModeController.add(value);
    return value;
  }

  Future<String?> _getCookieHeader() async {
    final cookiesString = await settings.getKey('cookies');
    if (cookiesString.isEmpty) {
      return null;
    }

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

    return cookiePairs.join('; ');
  }

  /// Parses user identity from portal homepage HTML ('/')
  Map<String, String> parsePortalHomeHtml(String homeHtml) {
    final result = <String, String>{};
    try {
      final doc = html_parser.parse(homeHtml);

      // 1. Name extraction
      // Check #greetTxt e.g. <h1 id="greetTxt"><img id="stu_img" src="photo.php" /><b>Good Afternoon, </b> Kaleb Fletcher </h1>
      final greetEl = doc.querySelector('#greetTxt, .greetTxt, h1#greetTxt');
      if (greetEl != null) {
        final text = greetEl.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        final greetMatch = RegExp(
          r"(?:Good\s+(?:Morning|Afternoon|Evening|Day)|Welcome|Hello|Hi),?\s*([A-Za-z\s'-]+)",
          caseSensitive: false,
        ).firstMatch(text);
        if (greetMatch != null) {
          final name = greetMatch.group(1)?.trim() ?? '';
          if (name.isNotEmpty &&
              name.toLowerCase() != 'to the portal' &&
              name.toLowerCase() != 'to nscg') {
            result['name'] = name;
          }
        }
      }

      if (!result.containsKey('name')) {
        final headers = doc.querySelectorAll('h1, h2, h3, h4, h5, h6');
        for (final h in headers) {
          final text = h.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          final welcomeMatch = RegExp(
            r"(?:Good\s+(?:Morning|Afternoon|Evening|Day)|Welcome|Hello|Hi),?\s*([A-Za-z\s'-]+)",
            caseSensitive: false,
          ).firstMatch(text);
          if (welcomeMatch != null) {
            final name = welcomeMatch.group(1)?.trim() ?? '';
            if (name.isNotEmpty &&
                name.toLowerCase() != 'to the portal' &&
                name.toLowerCase() != 'to nscg') {
              result['name'] = name;
              break;
            }
          }
        }
      }

      if (!result.containsKey('name')) {
        final sessionNameMatch = RegExp(
          r"\[(?:forename|name|fullname|user_name|display_name)\]\s*=>\s*([^\r\n\[\]]+)",
          caseSensitive: false,
        ).firstMatch(homeHtml);
        if (sessionNameMatch != null) {
          final name = sessionNameMatch.group(1)?.trim() ?? '';
          if (name.isNotEmpty && !name.contains('=>')) {
            result['name'] = name;
          }
        }
      }

      // 2. Ref Number extraction
      final scriptRefMatch = RegExp(
        r'''refNo\s*=\s*["']?([0-9]{4,10})["']?''',
        caseSensitive: false,
      ).firstMatch(homeHtml);
      final sessionRefMatch = RegExp(
        r"\[refNo\]\s*=>\s*([0-9]+)",
      ).firstMatch(homeHtml);
      final attrRefMatch = RegExp(
        r'''refNo=["']([0-9]{4,10})["']''',
        caseSensitive: false,
      ).firstMatch(homeHtml);

      final foundRef = scriptRefMatch?.group(1)?.trim() ??
          sessionRefMatch?.group(1)?.trim() ??
          attrRefMatch?.group(1)?.trim() ??
          '';

      if (foundRef.isNotEmpty) {
        result['ref'] = foundRef;
      }

      // 3. Username / ID extraction
      final commentUserMatch = RegExp(
        r'<!--\s*([cCsS][0-9]{5,8})\b',
      ).firstMatch(homeHtml);
      final sessionUserMatch = RegExp(
        r"\[username\]\s*=>\s*([A-Za-z0-9_@.-]+)",
      ).firstMatch(homeHtml);
      final emailMatch = RegExp(
        r"([a-zA-Z0-9._%+-]+@(?:stafford|nulc|nscg)\.ac\.uk)",
        caseSensitive: false,
      ).firstMatch(homeHtml);

      final foundUser = commentUserMatch?.group(1)?.trim() ??
          sessionUserMatch?.group(1)?.trim() ??
          emailMatch?.group(1)?.split('@').first.trim() ??
          (foundRef.isNotEmpty ? 'c$foundRef' : '');

      if (foundUser.isNotEmpty) {
        result['username'] = foundUser;
      }

      if (!result.containsKey('ref') && foundUser.isNotEmpty) {
        final digits = foundUser.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.isNotEmpty) {
          result['ref'] = digits;
        }
      }
    } catch (_) {}
    return result;
  }

  /// Fetches and saves user profile identity data (Name, College ID/Username, Ref No)
  /// independently of timetable schedule data.
  Future<Map<String, String>> fetchUserProfile() async {
    final result = <String, String>{};
    try {
      final cookieHeader = await _getCookieHeader();
      if (cookieHeader == null || cookieHeader.isEmpty) {
        return result;
      }

      // 1. Fetch main portal homepage ('/') for refNo, username, and user info
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
          final parsed = parsePortalHomeHtml(homeHtml);

          if (parsed['name'] != null && parsed['name']!.isNotEmpty) {
            await settings.setKey('timetableOwner', parsed['name']!);
            result['name'] = parsed['name']!;
          }
          if (parsed['ref'] != null && parsed['ref']!.isNotEmpty) {
            await settings.setKey('timetableOwnerRef', parsed['ref']!);
            result['ref'] = parsed['ref']!;
          }
          if (parsed['username'] != null && parsed['username']!.isNotEmpty) {
            await settings.setKey('timetableOwnerId', parsed['username']!);
            result['username'] = parsed['username']!;
          }
        }
      } catch (_) {}

      // 2. Fetch /studentTT/ to extract owner's name even if timetable has no lessons
      try {
        final ttResp = await _dio.get<String>(
          '/studentTT/',
          options: Options(
            headers: {'Cookie': cookieHeader, 'Accept': 'text/html'},
            responseType: ResponseType.plain,
          ),
        );

        if (ttResp.statusCode == 200 && ttResp.data != null) {
          final owner = Timetable.extractOwnerName(ttResp.data!);
          if (owner != null && owner.isNotEmpty) {
            final normalized = owner.replaceAll(RegExp(r'\s+'), ' ').trim();
            await settings.setKey('timetableOwner', normalized);
            result['name'] = normalized;
          }
        }
      } catch (_) {}

      // 3. Fallback: check /exams/ if name is still empty
      final currentOwner = await settings.getKey('timetableOwner');
      if (currentOwner.isEmpty) {
        try {
          final examResp = await _dio.get<String>(
            '/exams/',
            options: Options(
              headers: {'Cookie': cookieHeader, 'Accept': 'text/html'},
              responseType: ResponseType.plain,
            ),
          );
          if (examResp.statusCode == 200 && examResp.data != null) {
            final examTimetable = ExamTimetable.fromHtml(examResp.data!);
            if (examTimetable.studentInfo?.name != null &&
                examTimetable.studentInfo!.name.isNotEmpty) {
              final examName = examTimetable.studentInfo!.name.trim();
              await settings.setKey('timetableOwner', examName);
              result['name'] = examName;
              if (examTimetable.studentInfo?.candidateNo != null &&
                  examTimetable.studentInfo!.candidateNo.isNotEmpty) {
                final candNo = examTimetable.studentInfo!.candidateNo.trim();
                await settings.setKey('timetableOwnerRef', candNo);
                result['ref'] = candNo;
              } else if (examTimetable.studentInfo?.refNo != null &&
                  examTimetable.studentInfo!.refNo.isNotEmpty) {
                final refNo = examTimetable.studentInfo!.refNo.trim();
                await settings.setKey('timetableOwnerRef', refNo);
                result['ref'] = refNo;
              }
            }
          }
        } catch (_) {}
      }
    } catch (_) {}

    return result;
  }

  Future<Timetable?> getTimeTable({bool notifyWatch = true}) async {
    try {
      final isDebug = await settings.getBool('debugMode', defaultValue: false);
      if (isDebug) {
        final existing = await settings.getMap('timetable');
        if (existing.isNotEmpty) {
          try {
            return Timetable.fromJson(Map<String, dynamic>.from(existing));
          } catch (_) {}
        }
      }

      final cookieHeader = await _getCookieHeader();
      if (cookieHeader == null || cookieHeader.isEmpty) {
        debugPrint('[NSCGRequests] getTimeTable: No cookies available');
        return null;
      }

      debugPrint('[NSCGRequests] getTimeTable: GET /studentTT/ requesting...');
      final response = await _dio.get<String>(
        '/studentTT/',
        options: Options(
          headers: {'Cookie': cookieHeader, 'Accept': 'text/html'},
          responseType: ResponseType.plain,
        ),
      );

      debugPrint('[NSCGRequests] getTimeTable: status=${response.statusCode}, realUri=${response.realUri}');
      if (response.statusCode == 200 &&
          response.data != null &&
          response.realUri.toString().contains('studentTT/')) {
        Timetable timetable = Timetable.fromHtml(response.data!);
        debugPrint('[NSCGRequests] getTimeTable: parsed timetable with ${timetable.days.length} days');

        // Extract user profile info (name, refNo, username)
        await fetchUserProfile();

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
      final isDebug = await settings.getBool('debugMode', defaultValue: false);
      if (isDebug) {
        final existing = await settings.getMap('examTimetable');
        if (existing.isNotEmpty) {
          try {
            return ExamTimetable.fromJson(Map<String, dynamic>.from(existing));
          } catch (_) {}
        }
      }

      final cookieHeader = await _getCookieHeader();
      if (cookieHeader == null || cookieHeader.isEmpty) {
        return null;
      }

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
