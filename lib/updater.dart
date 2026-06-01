import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get_it/get_it.dart';
import 'package:nscgschedule/notifications.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class UpdaterScreen extends StatefulWidget {
  const UpdaterScreen({super.key});

  @override
  UpdaterScreenState createState() => UpdaterScreenState();
}

class UpdaterScreenState extends State<UpdaterScreen> {
  bool _loading = true;
  bool _error = false;
  NSCGScheduleLatest? _latestRelease;
  String _currentVersion = '0.0.0';
  double _progress = 0.0;
  bool _buttonEnabled = true;

  Future<bool> _hasInstallPackagesPermission() async {
    final status = await Permission.requestInstallPackages.status;
    if (status.isGranted) return true;

    // Try requesting if it's a normal denied state
    if (status.isDenied) {
      final result = await Permission.requestInstallPackages.request();
      if (result.isGranted) return true;
    }

    // If we reach here, permission isn't granted (could be permanently denied)
    if (!mounted) return false;
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Install permissions required'),
        content: const Text(
          'To install updates directly, enable "Install unknown apps" for this app in system settings. Open app settings now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (open == true) {
      await openAppSettings();
    }
    return false;
  }

  Future _load() async {
    // Load current version
    PackageInfo info = await PackageInfo.fromPlatform();
    String versionString = info.version;

    // Parse the version string
    if (mounted) {
      setState(() {
        _currentVersion = versionString.contains('-')
            ? versionString.split('-')[0]
            : versionString;
      });
    }

    //Load from website
    try {
      NSCGScheduleLatest latestRelease = await NSCGScheduleLatest.fetch();
      if (mounted) {
        setState(() {
          _latestRelease = latestRelease;
          _loading = false;
        });
      }
    } catch (e, st) {
      Logger.root.severe('Failed to load latest release', e, st);
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      } else {
        _error = true;
        _loading = false;
      }
    }
  }

  NSCGScheduleDownload? get _versionDownload {
    // Prefer an APK asset if present, otherwise return the first available download
    final downloads = _latestRelease?.downloads;
    if (downloads == null || downloads.isEmpty) return null;
    final apk = downloads.firstWhereOrNull(
      (d) => d.directUrl.toLowerCase().endsWith('.apk'),
    );
    return apk ?? downloads.first;
  }

  Future _download() async {
    if (!await _hasInstallPackagesPermission()) {
      Fluttertoast.showToast(
        msg: 'Permission denied, download canceled!',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
      );
      if (mounted) {
        setState(() {
          _progress = 0.0;
          _buttonEnabled = true;
        });
      } else {
        _progress = 0.0;
        _buttonEnabled = true;
      }
      return;
    }

    try {
      String? url = _versionDownload?.directUrl;
      if (url == null) {
        throw Exception('No compatible download available');
      }
      //Start request
      http.Client client = http.Client();
      http.StreamedResponse res = await client.send(
        http.Request('GET', Uri.parse(url)),
      );
      int? size = res.contentLength;
      //Open file
      String path = p.join(
        (await getExternalStorageDirectory())!.path,
        'update.apk',
      );
      File file = File(path);
      IOSink fileSink = file.openWrite();
      //Update progress
      Future.doWhile(() async {
        int received = await file.length();
        if (mounted) {
          setState(() => _progress = received / size!.toInt());
        }
        return received != size;
      });
      //Pipe
      await res.stream.pipe(fileSink);
      fileSink.close();

      OpenFilex.open(path);
      if (mounted) {
        setState(() {
          _buttonEnabled = true;
          _progress = 0.0;
        });
      } else {
        _buttonEnabled = true;
        _progress = 0.0;
      }
    } catch (e) {
      Logger.root.severe('Failed to download latest release file', e);
      Fluttertoast.showToast(
        msg: 'Download failed!',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
      );
      if (mounted) {
        setState(() {
          _progress = 0.0;
          _buttonEnabled = true;
        });
      } else {
        _progress = 0.0;
        _buttonEnabled = true;
      }
    }
  }

  Future _downloadUrl(String url) async {
    if (!await _hasInstallPackagesPermission()) {
      Fluttertoast.showToast(
        msg: 'Permission denied, download canceled!',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
      );
      if (mounted) {
        setState(() {
          _progress = 0.0;
          _buttonEnabled = true;
        });
      } else {
        _progress = 0.0;
        _buttonEnabled = true;
      }
      return;
    }

    try {
      http.Client client = http.Client();
      http.StreamedResponse res = await client.send(
        http.Request('GET', Uri.parse(url)),
      );
      int? size = res.contentLength;
      String path = p.join(
        (await getExternalStorageDirectory())!.path,
        'update.apk',
      );
      File file = File(path);
      IOSink fileSink = file.openWrite();
      Future.doWhile(() async {
        int received = await file.length();
        if (size != null && size > 0) {
          if (mounted) {
            setState(() => _progress = received / size.toInt());
          }
        }
        return received != size;
      });
      await res.stream.pipe(fileSink);
      fileSink.close();

      OpenFilex.open(path);
      if (mounted) {
        setState(() {
          _buttonEnabled = true;
          _progress = 0.0;
        });
      } else {
        _buttonEnabled = true;
        _progress = 0.0;
      }
    } catch (e) {
      Logger.root.severe('Failed to download file', e);
      Fluttertoast.showToast(
        msg: 'Download failed!',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
      );
      if (mounted) {
        setState(() {
          _progress = 0.0;
          _buttonEnabled = true;
        });
      } else {
        _progress = 0.0;
        _buttonEnabled = true;
      }
    }
  }

  @override
  void initState() {
    _load();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool hasUpdate =
        _latestRelease != null && _latestRelease!.version != _currentVersion;
    return Scaffold(
      appBar: AppBar(title: const Text('Updates')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _loading
            ? Center(child: CircularProgressIndicator(color: cs.primary))
            : _error
            ? Center(
                child: Card(
                  color: cs.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Failed to load updates',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: 16.0,
                          left: 16.0,
                          right: 16.0,
                          bottom: 4.0,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.system_update,
                                  size: 40,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        hasUpdate
                                            ? 'New update available'
                                            : 'You are up to date',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      if (_latestRelease != null)
                                        Text(
                                          '${_latestRelease!.version} • Current: $_currentVersion',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: hasUpdate && _buttonEnabled
                                          ? () {
                                              setState(
                                                () => _buttonEnabled = false,
                                              );
                                              _download();
                                            }
                                          : null,
                                      child: const Text('Download'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () async {
                                        final uri = Uri.parse(
                                          'https://github.com/kalebfletcher/nscgschedule/releases/latest',
                                        );
                                        if (await canLaunchUrl(uri)) {
                                          await launchUrl(
                                            uri,
                                            mode:
                                                LaunchMode.externalApplication,
                                          );
                                        }
                                      },
                                      child: const Text('Release page'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    // Separate card for the release title
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Release Title',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _latestRelease?.title ?? '',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Changelog',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Markdown(
                              shrinkWrap: true,
                              data: _latestRelease?.changelog ?? '',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (hasUpdate &&
                        (_latestRelease?.downloads.isNotEmpty ?? false))
                      ..._latestRelease!.downloads.map(
                        (d) => Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: FilledButton(
                            onPressed: _buttonEnabled
                                ? () {
                                    setState(() => _buttonEnabled = false);
                                    _downloadUrl(d.directUrl);
                                  }
                                : null,
                            child: const Text('Download & install'),
                          ),
                        ),
                      ),

                    if (_progress > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: LinearProgressIndicator(
                          value: _progress,
                          color: cs.primary,
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class NSCGScheduleLatest {
  final String versionString;
  final String title;
  final String version;
  final String changelog;
  final List<NSCGScheduleDownload> downloads;

  NSCGScheduleLatest({
    required this.versionString,
    required this.title,
    required this.changelog,
    required this.downloads,
  }) : version = versionString.contains('-')
           ? versionString.split('-')[0]
           : versionString;

  static Future<NSCGScheduleLatest> fetch() async {
    http.Response res = await http.get(
      Uri.parse(
        'https://api.github.com/repos/kalebfletcher/nscgschedule/releases/latest',
      ),
      headers: {'Accept': 'application/vnd.github.v3+json'},
    );

    if (res.statusCode != 200) {
      throw Exception(
        'Failed to load latest version from Github API: $res.statusCode $res.statusMessage',
      );
    }

    Map<String, dynamic> data = jsonDecode(res.body);

    List<NSCGScheduleDownload> downloads = (data['assets'] as List).map((
      asset,
    ) {
      return NSCGScheduleDownload(
        name: asset['name'] ?? '',
        directUrl: asset['browser_download_url'],
      );
    }).toList();

    return NSCGScheduleLatest(
      versionString: data['tag_name'],
      title: (data['name'] as String?) ?? (data['tag_name'] as String? ?? ''),
      changelog: data['body'] ?? '',
      downloads: downloads,
    );
  }

  static Future<void> checkUpdate() async {
    try {
      final latestVersion = await fetch();

      //Load current version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version.contains('-')
          ? packageInfo.version.split('-')[0]
          : packageInfo.version;

      if (latestVersion.version == currentVersion) return;

      // Do not enforce architecture-specific assets — pick any available APK (universal builds supported)

      //Show notification
      // Prefer the app-registered NotificationService to avoid re-initializing
      // and wiping any handlers. Fall back to a new instance if not registered.
      NotificationService notifService;
      try {
        notifService = GetIt.I<NotificationService>();
      } catch (_) {
        notifService = NotificationService();
        // Initialize fallback instance (no handler) — best effort
        try {
          await notifService.init();
        } catch (_) {}
      }
      final flutterLocalNotificationsPlugin =
          notifService.flutterLocalNotificationsPlugin;

      // Ensure Android channel exists (some devices need explicit channel creation)
      try {
        final androidImpl = flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (androidImpl != null) {
          const channel = AndroidNotificationChannel(
            'nscgscheduleupdates',
            'NSCGSchedule Updates',
            description: 'NSCGSchedule update notifications',
            importance: Importance.high,
          );
          await androidImpl.createNotificationChannel(channel);
        }
      } catch (e) {
        Logger.root.warning('Failed to create notification channel: $e');
      }

      AndroidNotificationDetails androidNotificationDetails =
          AndroidNotificationDetails(
            'nscgscheduleupdates',
            'NSCGSchedule Updates',
            channelDescription: 'NSCGSchedule Updates',
            importance: Importance.high,
            priority: Priority.high,
            // Keep visible until user interacts
            autoCancel: true,
          );

      final darwin = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: darwin,
        macOS: darwin,
      );

      // payload 'updater' will be handled in main.dart to navigate user
      await flutterLocalNotificationsPlugin.show(
        id: 0,
        title: 'New update available!',
        body: 'Tap to open updates and install the latest version.',
        notificationDetails: notificationDetails,
        payload: 'updater',
      );
    } catch (e) {
      Logger.root.severe('Error checking for updates', e);
    }
  }
}

class NSCGScheduleDownload {
  final String name;
  final String directUrl;

  NSCGScheduleDownload({required this.name, required this.directUrl});
}
