import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nscgschedule/requests.dart';
import 'package:nscgschedule/settings.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:get_it/get_it.dart';
import 'package:nscgschedule/notifications.dart';
import 'package:nscgschedule/badges_service.dart';
import 'package:nscgschedule/services/timetable_sync_service.dart';
import 'package:nscgschedule/debug_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isDarkMode = false;
  bool _useSystemTheme = true;
  bool _useMaterialYou = true;
  bool _dynamicFriendHeaderColor = false;
  bool _notificationsEnabled = true;
  bool _notifyOnStartTime = true;
  bool _notifyMinutesBeforeEnabled = true;
  int _notifyMinutesBefore = 5;
  bool _supportsMaterialYou = false;
  PackageInfo? _packageInfo;
  late final ValueNotifier<ThemeMode> _themeNotifier;
  final _materialYouNotifier = ValueNotifier<bool>(false);
  final TextEditingController _minutesBeforeController =
      TextEditingController();
  final TextEditingController _testMinutesController = TextEditingController(
    text: '1',
  );
  bool _debugMode = false;
  Map<String, dynamic>? _version;
  final NSCGRequests _requests = NSCGRequests.instance;
  final TimetableSyncService _syncService = GetIt.I<TimetableSyncService>();
  String _syncServerUrl = TimetableSyncService.defaultServerUrl;
  bool _onlineSyncEnabled = false;
  bool _privacyPolicyAccepted = false;

  @override
  void initState() {
    super.initState();
    _themeNotifier = ValueNotifier(ThemeMode.system);
    _loadPreferences().then((_) {
      // Check Material You support after loading preferences
      if (mounted) {
        setState(() {
          _materialYouNotifier.value = _useMaterialYou;
        });
      }
    });
    init();
  }

  Future<void> init() async {
    final debugMode = await settings.getBool('debugMode');
    final update = await NSCGRequests.instance.updateApp();
    setState(() {
      _version = update;
      _debugMode = debugMode;
    });
  }

  @override
  void dispose() {
    _themeNotifier.dispose();
    _materialYouNotifier.dispose();
    _minutesBeforeController.dispose();
    _testMinutesController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    _useSystemTheme = await settings.getUseSystemTheme();
    _isDarkMode = await settings.getDarkMode();
    _useMaterialYou = await settings.getUseMaterialYou();
    _dynamicFriendHeaderColor = await settings.getDynamicFriendHeaderColor();
    _notificationsEnabled = await settings.getNotificationsEnabled();
    _notifyOnStartTime = await settings.getNotifyOnStartTime();
    _notifyMinutesBeforeEnabled = await settings
        .getNotifyMinutesBeforeEnabled();
    _notifyMinutesBefore = await settings.getNotifyMinutesBefore();
    _minutesBeforeController.text = _notifyMinutesBefore.toString();
    _packageInfo = await PackageInfo.fromPlatform();
    _syncServerUrl = await _syncService.getServerUrl();
    _onlineSyncEnabled = await _syncService.isOnlineSyncEnabled();
    _privacyPolicyAccepted = await _syncService.isPrivacyPolicyAccepted();

    if (mounted) {
      setState(() {
        _themeNotifier.value = _useSystemTheme
            ? ThemeMode.system
            : _isDarkMode
            ? ThemeMode.dark
            : ThemeMode.light;
      });
    }
  }

  Future<void> _updateTheme(bool isDarkMode) async {
    await settings.setDarkMode(isDarkMode);
    if (mounted) {
      setState(() {
        _isDarkMode = isDarkMode;
        if (!_useSystemTheme) {
          _themeNotifier.value = isDarkMode ? ThemeMode.dark : ThemeMode.light;
        }
      });
    }
  }

  Future<void> _updateSystemTheme(bool useSystem) async {
    await settings.setUseSystemTheme(useSystem);
    if (mounted) {
      setState(() {
        _useSystemTheme = useSystem;
        _themeNotifier.value = useSystem
            ? ThemeMode.system
            : _isDarkMode
            ? ThemeMode.dark
            : ThemeMode.light;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? normalizedPackageVersion = _packageInfo?.version == null
        ? null
        : (_packageInfo!.version.contains('-')
              ? _packageInfo!.version.split('-')[0]
              : _packageInfo!.version);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        // leading: IconButton(
        //   icon: const Icon(Icons.arrow_back),
        //   onPressed: () => context.pop(),
        // ),
      ),
      body: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          final supportsMaterialYou =
              lightDynamic != null && darkDynamic != null;
          if (_supportsMaterialYou != supportsMaterialYou) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _supportsMaterialYou = supportsMaterialYou;
                  if (!_supportsMaterialYou) {
                    _materialYouNotifier.value = false;
                    settings.setUseMaterialYou(false);
                  }
                });
              }
            });
          }

          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: _themeNotifier,
                builder: (context, themeMode, _) {
                  return Column(
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: _materialYouNotifier,
                        builder: (context, useMaterialYou, _) {
                          return SwitchListTile(
                            title: const Text('Material You'),
                            subtitle: _supportsMaterialYou
                                ? const Text(
                                    'Use dynamic theming based on wallpaper',
                                  )
                                : const Text(
                                    'Not supported on this device',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                            value: _supportsMaterialYou && useMaterialYou,
                            onChanged: _supportsMaterialYou
                                ? (value) async {
                                    await settings.setUseMaterialYou(value);
                                    if (mounted) {
                                      setState(() {
                                        _useMaterialYou = value;
                                        _materialYouNotifier.value = value;
                                      });
                                    }
                                  }
                                : null,
                            secondary: Icon(
                              Icons.palette,
                              color: _supportsMaterialYou ? null : Colors.grey,
                            ),
                          );
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Use System Theme'),
                        subtitle: const Text('Match system light/dark theme'),
                        value: _useSystemTheme,
                        onChanged: _updateSystemTheme,
                        secondary: const Icon(Icons.phone_android),
                      ),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _useSystemTheme ? 0.6 : 1.0,
                        child: IgnorePointer(
                          ignoring: _useSystemTheme,
                          child: SwitchListTile(
                            title: const Text('Dark Mode'),
                            subtitle: _useSystemTheme
                                ? const Text('Using system theme')
                                : const Text('Toggle dark mode'),
                            value: _isDarkMode,
                            onChanged: _updateTheme,
                            secondary: Icon(
                              _isDarkMode ? Icons.dark_mode : Icons.light_mode,
                            ),
                          ),
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('Dynamic Friend Colors'),
                        subtitle: const Text('Color friend profiles based on their picture'),
                        value: _dynamicFriendHeaderColor,
                        onChanged: (value) async {
                          await settings.setDynamicFriendHeaderColor(value);
                          if (mounted) {
                            setState(() {
                              _dynamicFriendHeaderColor = value;
                            });
                          }
                        },
                        secondary: const Icon(Icons.format_paint),
                      ),
                    ],
                  );
                },
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Notifications',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SwitchListTile(
                title: const Text('Enable Notifications'),
                value: _notificationsEnabled,
                onChanged: (value) async {
                  await settings.setNotificationsEnabled(value);
                  setState(() {
                    _notificationsEnabled = value;
                  });
                },
                secondary: const Icon(Icons.notifications),
              ),
              SwitchListTile(
                title: const Text('Notify on lesson start'),
                value: _notifyOnStartTime,
                onChanged: _notificationsEnabled
                    ? (value) async {
                        await settings.setNotifyOnStartTime(value);
                        setState(() {
                          _notifyOnStartTime = value;
                        });
                      }
                    : null,
                secondary: const Icon(Icons.timer),
              ),
              SwitchListTile(
                title: const Text('Enable "minutes before" notification'),
                value: _notifyMinutesBeforeEnabled,
                onChanged: _notificationsEnabled
                    ? (value) async {
                        await settings.setNotifyMinutesBeforeEnabled(value);
                        setState(() {
                          _notifyMinutesBeforeEnabled = value;
                        });
                      }
                    : null,
                secondary: const Icon(Icons.timer_10),
              ),
              ListTile(
                leading: const SizedBox(width: 0),
                title: const Text('Minutes before (custom)'),
                subtitle: const Text('Enter any number of minutes'),
                trailing: SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _minutesBeforeController,
                    enabled:
                        _notificationsEnabled && _notifyMinutesBeforeEnabled,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'e.g. 7',
                      isDense: true,
                    ),
                    onSubmitted: (value) async {
                      final parsed = int.tryParse(value.trim());
                      if (parsed != null && parsed >= 0 && parsed <= 240) {
                        await settings.setNotifyMinutesBefore(parsed);
                        setState(() {
                          _notifyMinutesBefore = parsed;
                        });
                      } else {
                        // Reset to current valid value
                        _minutesBeforeController.text = _notifyMinutesBefore
                            .toString();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please enter a valid number between 0 and 240',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Schedule Sync',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SwitchListTile(
                title: const Text('Enable Online Sync'),
                subtitle: const Text(
                  'Keep timetables synchronized in real time with friends',
                ),
                secondary: const Icon(Icons.cloud_sync_outlined),
                value: _onlineSyncEnabled,
                onChanged: (bool value) async {
                  if (value) {
                    final accepted = await _syncService.isPrivacyPolicyAccepted();
                    if (!accepted) {
                      if (context.mounted) {
                        await context.push('/settings/privacy-policy');
                        final nowOnline = await _syncService.isOnlineSyncEnabled();
                        final nowAccepted = await _syncService.isPrivacyPolicyAccepted();
                        if (mounted) {
                          setState(() {
                            _onlineSyncEnabled = nowOnline;
                            _privacyPolicyAccepted = nowAccepted;
                          });
                        }
                      }
                      return;
                    } else {
                      await _syncService.setOnlineSyncEnabled(true);
                      if (mounted) {
                        setState(() {
                          _onlineSyncEnabled = true;
                          _privacyPolicyAccepted = true;
                        });
                      }
                    }
                  } else {
                    await _syncService.setOnlineSyncEnabled(false);
                    if (mounted) {
                      setState(() => _onlineSyncEnabled = false);
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Online Sync Privacy & Terms'),
                subtitle: const Text(
                  'Review end-to-end encryption and terms of use',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await context.push('/settings/privacy-policy');
                  if (mounted) {
                    final online = await _syncService.isOnlineSyncEnabled();
                    final accepted = await _syncService.isPrivacyPolicyAccepted();
                    setState(() {
                      _onlineSyncEnabled = online;
                      _privacyPolicyAccepted = accepted;
                    });
                  }
                },
              ),
              if (_onlineSyncEnabled && _privacyPolicyAccepted) ...[
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Sync All Online Friends'),
                  subtitle: const Text('Fetch latest schedules from sync server'),
                  onTap: () async {
                    await _syncService.syncAllFriends();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.devices_outlined),
                  title: const Text('Manage Connected Devices'),
                  subtitle: const Text(
                    'View and manage friends with access to your schedule',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.push('/friends/sync-access');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('Regenerate Invite Keys'),
                  subtitle: const Text(
                    'Invalidate old invite QR codes and links',
                  ),
                  onTap: () async {
                    final isPublished = await _syncService.isTimetablePublished();
                    if (!context.mounted) return;
                    if (!isPublished) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'You have not shared a timetable yet. Share your timetable first to create invite keys.',
                          ),
                        ),
                      );
                      return;
                    }

                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Regenerate Invite Keys?'),
                        content: const Text(
                          'This will invalidate all previously shared invite QR codes and links.\n\n'
                          'Existing connected friends will keep access, but anyone scanning an older QR code will not be able to connect.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Regenerate'),
                          ),
                        ],
                      ),
                    );

                    if (confirm != true || !context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Regenerating invite keys...'),
                        duration: Duration(seconds: 1),
                      ),
                    );

                    try {
                      await _syncService.regenerateInviteKeys();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Invite keys successfully regenerated. New QR codes will now be used for sharing.',
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to regenerate invite keys: $e'),
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Delete Timetable from Server',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  subtitle: const Text(
                    'Permanently remove your timetable and revoke all shared access',
                  ),
                  onTap: () async {
                    final isPublished = await _syncService.isTimetablePublished();
                    if (!context.mounted) return;
                    if (!isPublished) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'You have not shared or published a timetable to the server yet.',
                          ),
                        ),
                      );
                      return;
                    }

                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Timetable from Server?'),
                        content: const Text(
                          'This will permanently delete your published timetable from the sync server, revoke all shared access, remove any online timetables from other people, and opt you out of Online Sync.\n\n'
                          'All connected friends will immediately lose access. This action cannot be undone.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.error,
                              foregroundColor:
                                  Theme.of(context).colorScheme.onError,
                            ),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete & Opt Out'),
                          ),
                        ],
                      ),
                    );

                    if (confirm != true || !context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Deleting timetable and opting out...'),
                        duration: Duration(seconds: 1),
                      ),
                    );

                    try {
                      await _syncService.deletePublishedTimetable();
                      if (!context.mounted) return;
                      setState(() {
                        _onlineSyncEnabled = false;
                        _privacyPolicyAccepted = false;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Timetable deleted from server and opted out of Online Sync.',
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to delete timetable: $e'),
                        ),
                      );
                    }
                  },
                ),
              ],
              const Divider(),
              ListTile(
                leading: const Icon(Icons.update),
                title: const Text('Updates'),
                subtitle: Text(
                  _version == null
                      ? 'Checking...'
                      : (_version!['version'] == normalizedPackageVersion)
                      ? 'You are up to date'
                      : 'Update available',
                ),
                trailing:
                    _version != null &&
                        _version!['version'] != normalizedPackageVersion
                    ? const Icon(Icons.arrow_forward_ios)
                    : null,
                onTap: () {
                  context.go('/settings/updates');
                },
              ),
              ListTile(
                title: const Text('About'),
                subtitle: Text(
                  'App version ${_packageInfo?.version ?? 'Loading...'}',
                ),
                leading: const Icon(Icons.info_outline),
                trailing: _debugMode
                    ? Badge(
                        padding: const EdgeInsets.all(4),
                        isLabelVisible: true,
                        label: Text('Debug Enabled'),
                      )
                    : null,
                onTap: () {
                  // Show about dialog
                  showAboutDialog(
                    context: context,
                    applicationName: 'NSCG Schedule',
                    applicationVersion: _packageInfo?.version ?? 'Loading...',
                    applicationIcon: Center(
                      child: Image.asset(
                        'assets/icon/icon.png',
                        width: 55,
                        height: 55,
                      ),
                    ),
                    children: [
                      Text('A Schedule/TimeTable app for NSCG students'),
                    ],
                  );
                },
                onLongPress: () async {
                  if (await settings.getBool('debugMode')) {
                    _requests.debugMode(false);
                    setState(() {
                      _debugMode = false;
                    });
                  } else {
                    _requests.debugMode(true);
                    setState(() {
                      _debugMode = true;
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () async {
                  await settings.setBool('loggedin', false);
                  // Notify listeners
                  try {
                    NSCGRequests.instance.loggedinController.add(false);
                  } catch (_) {}
                  // Clear stored timetables (use encrypted storage)
                  await settings.setMap('timetable', {});
                  await settings.setMap('examTimetable', {});
                  if (!context.mounted) return;
                  context.go('/');
                },
              ),
              if (_debugMode) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Debug Settings',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 8.0),
                  child: Text(
                    'Notification Tools',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('Reschedule notifications'),
                  subtitle: const Text(
                    'Recreates all notifications from current timetable and settings',
                  ),
                  onTap: () async {
                    final ns = GetIt.I<NotificationService>();
                    ns.requestReschedule();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Reschedule requested')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.list),
                  title: const Text('List pending notifications'),
                  onTap: () async {
                    final ns = GetIt.I<NotificationService>();
                    final pending = await ns.getPendingNotifications();
                    if (!context.mounted) return;
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('Pending (${pending.length})'),
                        content: SizedBox(
                          width: double.maxFinite,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: pending
                                  .map(
                                    (p) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4.0,
                                      ),
                                      child: Text(
                                        '#${p.id}: ${p.title ?? ''} — ${p.body ?? ''}',
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever),
                  title: const Text('Cancel all notifications'),
                  onTap: () async {
                    final ns = GetIt.I<NotificationService>();
                    await ns.cancelAllNotifications();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('All notifications cancelled'),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_active),
                  title: const Text('Schedule test notification'),
                  subtitle: const Text(
                    'Schedules a single test notification in N minute(s)',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 50,
                        child: TextField(
                          controller: _testMinutesController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '1',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final ns = GetIt.I<NotificationService>();
                          final m =
                              int.tryParse(
                                _testMinutesController.text.trim(),
                              ) ??
                              1;
                          await ns.scheduleTestNotification(minutesFromNow: m);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Test notification scheduled in $m minute(s)',
                              ),
                            ),
                          );
                        },
                        child: const Text('Go'),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.badge),
                  title: const Text('Refresh Badges (debug)'),
                  subtitle: const Text(
                    'Force download badges.json and cache images',
                  ),
                  onTap: () async {
                    final svc = BadgesService.instance;
                    final url = svc.remoteUrl;
                    if (url == null || url.isEmpty) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No remote badges URL configured'),
                        ),
                      );
                      return;
                    }
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Refreshing badges...')),
                    );
                    try {
                      await svc.fetchAndCache(url);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Badges refreshed')),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to refresh badges: $e')),
                      );
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                  child: Text(
                    'Mock Data Generator',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_month),
                  title: const Text('Generate Random Timetable'),
                  subtitle: const Text(
                    'Creates randomized classes for Mon-Fri and updates widgets',
                  ),
                  onTap: () async {
                    final tt =
                        await DebugService.instance.generateRandomTimetable();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Generated random timetable with ${tt.days.length} days!',
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.school),
                  title: const Text('Generate Random Exam Timetable'),
                  subtitle: const Text(
                    'Creates upcoming mock exams with student info & rooms',
                  ),
                  onTap: () async {
                    final et =
                        await DebugService.instance
                            .generateRandomExamTimetable();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Generated ${et.exams.length} upcoming mock exams!',
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('Generate Both (Timetable & Exams)'),
                  subtitle: const Text(
                    'Populates both regular schedule and exam schedule',
                  ),
                  onTap: () async {
                    await DebugService.instance.generateRandomTimetable();
                    await DebugService.instance
                        .generateRandomExamTimetable();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Generated mock timetable and exams!'),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.cleaning_services),
                  title: const Text('Clear Mock Timetable & Exams'),
                  subtitle: const Text(
                    'Empties timetable and exam timetable storage',
                  ),
                  onTap: () async {
                    await DebugService.instance.clearMockData();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Cleared timetable & exam data'),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                  child: Text(
                    'Sync Debug Tools',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('Sync Server URL'),
                  subtitle: Text(_syncServerUrl),
                  trailing: const Icon(Icons.edit),
                  onTap: () async {
                    final controller = TextEditingController(
                      text: _syncServerUrl,
                    );
                    final newUrl = await showDialog<String>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Sync Server URL'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Enter the base URL for the online timetable sync server:',
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                hintText: 'http://192.168.1.106:3000',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              controller.text =
                                  TimetableSyncService.defaultServerUrl;
                            },
                            child: const Text('Reset Default'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.pop(context, controller.text.trim()),
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    );

                    if (newUrl != null && newUrl.isNotEmpty) {
                      await _syncService.setServerUrl(newUrl);
                      final updatedUrl = await _syncService.getServerUrl();
                      setState(() => _syncServerUrl = updatedUrl);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Sync server updated to: $updatedUrl'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
