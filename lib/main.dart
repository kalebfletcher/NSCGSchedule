import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:nscgschedule/models/friend_models.dart';
import 'package:nscgschedule/router.dart';
import 'package:nscgschedule/settings.dart';
import 'package:nscgschedule/watch_service.dart';
import 'package:nscgschedule/widget_service.dart';
import 'package:nscgschedule/friends_service.dart';
import 'package:nscgschedule/debug_service.dart';
import 'dart:async';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:go_router/go_router.dart';
import 'package:nscgschedule/notifications.dart';
import 'package:nscgschedule/updater.dart';
import 'package:nscgschedule/badges_service.dart';
import 'package:nscgschedule/services/timetable_sync_service.dart';

final getIt = GetIt.instance;

// Pending notification payload (encoded) to process after app initialization if immediate navigation fails
String? pendingNotificationOpen;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  await _initServices();

  runApp(const MyApp());
}

Future<void> _initServices() async {
  // Initialize Hive for local storage
  await Hive.initFlutter();

  // Register Hive adapters (run: dart run build_runner build first)
  // Uncomment after running build_runner to generate friend_models.g.dart:
  Hive.registerAdapter(PrivacyLevelAdapter());
  Hive.registerAdapter(FriendAdapter());
  Hive.registerAdapter(FriendTimetableAdapter());
  Hive.registerAdapter(FriendDayScheduleAdapter());
  Hive.registerAdapter(FriendLessonAdapter());

  // Settings
  final settings = Settings();
  await settings.init();
  getIt.registerSingleton<Settings>(settings);

  // Debug service (centralized debug time)
  final debugService = DebugService.instance;
  await debugService.loadFromPrefs();
  getIt.registerSingleton<DebugService>(debugService);

  // Friends Service (will work after adapters are registered)
  final friendsService = FriendsService();
  await friendsService.init();
  getIt.registerSingleton<FriendsService>(friendsService);

  // Timetable Sync Service (online sharing and syncing)
  final timetableSyncService = TimetableSyncService();
  getIt.registerSingleton<TimetableSyncService>(timetableSyncService);

  // Notification Service
  final notificationService = NotificationService();
  await notificationService.init(
    onDidReceiveNotificationResponse: (response) {
      final payload = response.payload;
      if (payload == null || payload.isEmpty) return;

      if (payload.startsWith('exam:')) {
        final examKey = payload.substring('exam:'.length);
        final encoded = Uri.encodeComponent(examKey);
        // Use push so tapping a notification creates a back-entry and user can return
        try {
          routerController.push('/exams?open=$encoded');
        } catch (e) {
          // If navigation isn't ready yet (cold start), store for processing after app init
          pendingNotificationOpen = encoded;
        }
        return;
      }

      if (payload == 'updater' || payload.startsWith('updater:')) {
        try {
          // Open updates screen
          routerController.push('/settings/updates');
        } catch (e) {
          // store a token so we can navigate after router is ready
          pendingNotificationOpen = 'updater';
        }
        return;
      }
    },
  );
  getIt.registerSingleton<NotificationService>(notificationService);

  // Request permissions after initialization
  await notificationService.requestPermissions();

  // Watch Service for WearOS communication
  await WatchService.instance.init();

  // Initialize widget service and sync existing data
  await WidgetService.instance.syncAllToWidget();

  // Initialize badges system (will load cached data; optionally provide remote URL)
  try {
    BadgesService.instance.remoteUrl =
        'https://raw.githubusercontent.com/kalebfletcher/NSCGSchedule/refs/heads/main/badges.json';
    BadgesService.instance.init(
      remoteJsonUrl:
          'https://raw.githubusercontent.com/kalebfletcher/NSCGSchedule/refs/heads/main/badges.json',
    );
  } catch (_) {}
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _useSystemTheme = true;
  bool _useMaterialYou = true;
  ThemeMode _themeMode = ThemeMode.system;
  StreamSubscription<bool>? _themeChangeSubscription;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initTheme();
    // Lazily initialize badges after first frame so startup isn't blocked
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // start in background; don't await
      BadgesService.instance.init().catchError((_) {});
    });
    // Lazily sync online friends schedules and mailbox after startup animation completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 5), () {
        getIt<TimetableSyncService>().syncAllFriends().catchError((_) => 0);
        getIt<TimetableSyncService>().checkAndSyncMailbox().catchError((_) => <MailboxEntry>[]);
      });
    });
    // Run updater check once at startup and then once every 24 hours
    NSCGScheduleLatest.checkUpdate();
    _updateTimer = Timer.periodic(const Duration(hours: 24), (_) {
      NSCGScheduleLatest.checkUpdate();
    });
    // If a notification arrived before the app/router was ready, navigate now
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (pendingNotificationOpen != null) {
        try {
          if (pendingNotificationOpen == 'updater') {
            routerController.push('/settings/updates');
          } else {
            routerController.push('/exams?open=$pendingNotificationOpen');
          }
        } catch (e) {
          try {
            if (pendingNotificationOpen == 'updater') {
              routerController.go('/settings/updates');
            } else {
              routerController.go('/exams?open=$pendingNotificationOpen');
            }
          } catch (_) {
            // give up silently; nothing more we can do here
          }
        } finally {
          pendingNotificationOpen = null;
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reload debug time when app comes to foreground
      getIt<DebugService>().loadFromPrefs();
      // Sync friends and mailbox on resume, slightly delayed to avoid jank
      Future.delayed(const Duration(milliseconds: 1500), () {
        getIt<TimetableSyncService>().syncAllFriends().catchError((_) => 0);
        getIt<TimetableSyncService>().checkAndSyncMailbox().catchError((_) => <MailboxEntry>[]);
      });
    }
  }

  Future<void> _initTheme() async {
    await _loadThemePreferences();
    _themeChangeSubscription = getIt<Settings>().onThemeChanged.listen((
      _,
    ) async {
      if (mounted) {
        await _loadThemePreferences();
        if (mounted) {
          setState(() {
            // Force a rebuild when theme changes
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _themeChangeSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadThemePreferences() async {
    if (!mounted) return;

    try {
      final useSystemTheme = await getIt<Settings>().getUseSystemTheme();
      final isDarkMode = await getIt<Settings>().getDarkMode();
      final useMaterialYou = await getIt<Settings>().getUseMaterialYou();

      if (mounted) {
        setState(() {
          _useSystemTheme = useSystemTheme;
          _useMaterialYou = useMaterialYou;
          _themeMode = useSystemTheme
              ? ThemeMode.system
              : isDarkMode
              ? ThemeMode.dark
              : ThemeMode.light;
        });
      }
    } catch (e) {
      debugPrint('Error loading theme preferences: $e');
      if (mounted) {
        setState(() {
          _themeMode = ThemeMode.system;
          _useSystemTheme = true;
          _useMaterialYou = true;
        });
      }
    }
  }

  @override
  void didChangePlatformBrightness() {
    if (_useSystemTheme && mounted) {
      _loadThemePreferences();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // Define the seed color for the app
        const seedColor = Color.fromARGB(255, 255, 81, 0);

        // Use dynamic color if available and Material You is enabled, otherwise use fixed seed
        final supportsMaterialYou = lightDynamic != null && darkDynamic != null;

        final lightColorScheme = (_useMaterialYou && supportsMaterialYou)
            ? lightDynamic.harmonized()
            : ColorScheme.fromSeed(
                seedColor: seedColor,
                brightness: Brightness.light,
              );

        final darkColorScheme = (_useMaterialYou && supportsMaterialYou)
            ? darkDynamic.harmonized()
            : ColorScheme.fromSeed(
                seedColor: seedColor,
                brightness: Brightness.dark,
              );

        debugPrint(
          'Material You: $_useMaterialYou, Supported: $supportsMaterialYou',
        );

        return MaterialApp.router(
          routerConfig: routerController,
          title: 'NSCG Schedule',
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: lightColorScheme,
            brightness: Brightness.light,
            visualDensity: VisualDensity.adaptivePlatformDensity,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: darkColorScheme,
            brightness: Brightness.dark,
            visualDensity: VisualDensity.adaptivePlatformDensity,
          ),
          themeMode: _themeMode,
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (context.mounted) {
      context.go('/');
    }
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
