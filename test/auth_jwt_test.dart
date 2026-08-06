import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nscgschedule/requests.dart';
import 'package:nscgschedule/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Auth JWT & URL Process Tests', () {
    late Directory tempDir;
    final Map<String, String> mockSecureStorage = {};

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      mockSecureStorage.clear();
      tempDir = await Directory.systemTemp.createTemp('hive_auth_test');

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

      if (!GetIt.I.isRegistered<Settings>()) {
        GetIt.I.registerSingleton<Settings>(Settings());
        await settings.init();
      }
    });

    tearDownAll(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('processAuthUrl extracts username, ref, and upn from authToken JWT', () async {
      const authUrl =
          'https://my.nulc.ac.uk/?authToken=eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6IldCZ1dfUzJtUThtMlNrZU53RHZRM3U2a0w5YyIsImtpZCI6IldCZ1dfUzJtUThtMlNrZU53RHZRM3U2a0w5YyJ9.eyJhdWQiOiJ1cm46QXBwUHJveHk6Y29tIiwiaXNzIjoiaHR0cDovL2lkcC5udWxjLmFjLnVrL2FkZnMvc2VydmljZXMvdHJ1c3QiLCJpYXQiOjE3ODU4NTU3ODUsIm5iZiI6MTc4NTg1NTc4NSwiZXhwIjoxNzg1ODU5Mzg1LCJyZWx5aW5ncGFydHl0cnVzdGlkIjoiN2U4Mjc5N2ItZDg3NC1lZDExLWI4MTAtMDA1MDU2YTc0ODk3IiwidXBuIjoiYzI0Mzg3OUBzdGFmZm9yZC5hYy51ayIsImNsaWVudHJlcWlkIjoiYmM0MWM1MmYtMTRiYS0wMDAwLTE0OGMtZWNiZGJhMTRkZDAxIiwiYXV0aG1ldGhvZCI6InVybjpvYXNpczpuYW1lczp0YzpTQU1MOjIuMDphYzpjbGFzc2VzOlBhc3N3b3JkUHJvdGVjdGVkVHJhbnNwb3J0IiwiYXV0aF90aW1lIjoiMjAyNi0wOC0wNFQxNTowMzowNS4wODhaIiwidmVyIjoiMS4wIn0.DrNnphfP6ypVv_6';

      final res = await NSCGRequests.instance.processAuthUrl(authUrl);

      expect(res['username'], equals('c243879'));
      expect(res['ref'], equals('243879'));

      final savedId = await settings.getKey('timetableOwnerId');
      final savedRef = await settings.getKey('timetableOwnerRef');

      expect(savedId, equals('c243879'));
      expect(savedRef, equals('243879'));
    });

    test('parsePortalHomeHtml extracts name, ref, and username from portal HTML', () {
      const portalHtml = '''
<!--c243879 c243879 --><!-- maincourse: 193SFVIT051--><!--main.html--><!DOCTYPE html>
<html>
<head>
<title>
NSCG Student Homepage
</title>
<script>
refNo = "243879"
</script>
</head>
<body id="ragbag" >			  
<section class="hdr">
	<div id="mainheading" style="color:gray;">
	<h1 id="greetTxt">
<img id="stu_img" src="photo.php" /><b>Good Afternoon, </b> Kaleb Fletcher	</h1>
	</div>
</section>
</body>
</html>
''';

      final res = NSCGRequests.instance.parsePortalHomeHtml(portalHtml);

      expect(res['name'], equals('Kaleb Fletcher'));
      expect(res['ref'], equals('243879'));
      expect(res['username'], equals('c243879'));
    });
  });
}
