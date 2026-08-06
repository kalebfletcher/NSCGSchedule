import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nscgschedule/friends_service.dart';
import 'package:nscgschedule/models/friend_models.dart';
import 'package:nscgschedule/debug_service.dart';
import 'package:nscgschedule/edit_friend_bottom_sheet.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show File;
import 'dart:async';
import 'package:nscgschedule/badges_service.dart';
import 'package:nscgschedule/services/timetable_sync_service.dart';
import 'package:nscgschedule/friends_onboarding.dart';

class FriendsListScreen extends StatefulWidget {
  const FriendsListScreen({super.key});

  @override
  State<FriendsListScreen> createState() => _FriendsListScreenState();
}

class _FriendsListScreenState extends State<FriendsListScreen> {
  final FriendsService _friendsService = GetIt.I<FriendsService>();
  final TimetableSyncService _syncService = GetIt.I<TimetableSyncService>();
  final DebugService _debug = GetIt.I<DebugService>();
  List<Friend> _friends = [];
  Timer? _refreshTimer;
  bool _isSyncing = false;
  bool _onboardingChecked = false;
  bool _showOnboarding = false;
  bool _isOnlineSync = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
    _loadFriends();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<void> _loadSyncState() async {
    final isOnline = await _syncService.isOnlineSyncEnabled();
    final isAccepted = await _syncService.isPrivacyPolicyAccepted();
    if (mounted) {
      setState(() {
        _isOnlineSync = isOnline && isAccepted;
      });
    }
  }

  Future<void> _checkOnboarding() async {
    final completed = await _syncService.isFriendsOnboardingCompleted();
    await _loadSyncState();
    if (!mounted) return;
    setState(() {
      _showOnboarding = !completed;
      _onboardingChecked = true;
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _openScanScreen() async {
    try {
      final status = await Permission.camera.status;
      if (!status.isGranted) {
        await Permission.camera.request();
      }
    } catch (_) {}
    if (mounted) {
      await context.push('/friends/scan');
      _loadFriends();
    }
  }

  void _loadFriends() {
    _loadSyncState();
    setState(() {
      _friends = _friendsService.getAllFriends();
    });
  }

  Future<void> _syncAll() async {
    if (_isSyncing) return;
    final isOnline = await _syncService.isOnlineSyncEnabled();
    if (!isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Online sync is disabled. Enable it in Settings.'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => context.push('/settings'),
            ),
          ),
        );
      }
      return;
    }
    setState(() => _isSyncing = true);
    try {
      await _syncService.syncAllFriends();
      if (mounted) {
        _loadFriends();
      }
    } catch (_) {
      // Handled silently
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _showQrOptionsBottomSheet() async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code),
              title: const Text('Show My QR'),
              subtitle: const Text('Share your timetable with friends'),
              onTap: () => Navigator.pop(context, 0),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Scan Friend QR'),
              subtitle: const Text('Scan a friend\'s QR code to add them'),
              onTap: () => Navigator.pop(context, 1),
            ),
          ],
        ),
      ),
    );

    if (choice == 0 && mounted) {
      await context.push('/friends/share');
      _loadFriends();
    } else if (choice == 1 && mounted) {
      await _openScanScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_onboardingChecked) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_showOnboarding) {
      return FriendsOnboardingScreen(
        onContinueOffline: () {
          setState(() {
            _showOnboarding = false;
          });
          _loadFriends();
        },
        onEnableOnlineSync: () async {
          final result = await context.push('/friends/privacy-policy');
          final isEnabled = await _syncService.isOnlineSyncEnabled();
          if (result == true || isEnabled) {
            if (mounted) {
              setState(() {
                _showOnboarding = false;
              });
              _loadFriends();
              _syncAll();
            }
          }
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          if (_isOnlineSync)
            IconButton(
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              tooltip: 'Sync Online Friends',
              onPressed: _isSyncing ? null : _syncAll,
            ),
          if (_isOnlineSync)
            IconButton(
              icon: const Icon(Icons.devices_outlined),
              tooltip: 'Access Management',
              onPressed: () async {
                await context.push('/friends/sync-access');
                _loadFriends();
              },
            ),
          IconButton(
            icon: const Icon(Icons.qr_code),
            tooltip: 'QR Code Options',
            onPressed: _showQrOptionsBottomSheet,
          ),
        ],
      ),
      body: _friends.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _syncAll,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _friends.length,
                itemBuilder: (context, index) {
                  final friend = _friends[index];
                  return _buildFriendCard(friend);
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showQrOptionsBottomSheet,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Friend'),
      ),
    );
  }

  String _computeFriendSubtitle(Friend friend) {
    try {
      final now = _debug.enabled ? _debug.now : DateTime.now();
      const weekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      final today = weekdays[now.weekday - 1];
      final day = friend.timetable.days.firstWhere(
        (d) => d.weekday == today,
        orElse: () => FriendDaySchedule(weekday: today, lessons: []),
      );

      int toMins(String t) {
        return parseTimeToMinutes(t) ?? -1;
      }

      final nowM = now.hour * 60 + now.minute;

      if (day.lessons.isEmpty) return 'No classes today';

      // Convert lessons to minute ranges
      final ranges = day.lessons.map((l) {
        return MapEntry(l, [toMins(l.startTime), toMins(l.endTime)]);
      }).toList();

      if (friend.privacyLevel == PrivacyLevel.freeTimeOnly) {
        // lessons represent free periods
        for (final e in ranges) {
          final start = e.value[0];
          final end = e.value[1];
          if (start <= nowM && nowM < end) {
            return 'Free until ${e.key.endTime}';
          }
        }
        // find next free period
        final future = ranges.where((e) => e.value[0] > nowM).toList();
        if (future.isNotEmpty) {
          final f = future.first;
          return 'Free ${f.key.startTime}-${f.key.endTime}';
        }
        return 'Busy for the rest of today';
      }

      // busyBlocks or fullDetails -> lessons are busy
      for (final e in ranges) {
        final start = e.value[0];
        final end = e.value[1];
        if (start <= nowM && nowM < end) {
          final name = e.key.name ?? 'Class';
          final room = e.key.room != null && e.key.room!.isNotEmpty
              ? ' in ${e.key.room}'
              : '';
          return 'Busy — $name until ${e.key.endTime}$room';
        }
      }

      // Not in a lesson: free until next lesson or free all day
      final futureLessons = ranges.where((e) => e.value[0] > nowM).toList();
      if (futureLessons.isNotEmpty) {
        final next = futureLessons.first;
        return 'Free until ${next.key.startTime}';
      }
      return 'Free for the rest of today';
    } catch (_) {
      return '';
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 120,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'No Friends Yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Add friends to compare schedules and find mutual free time',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _openScanScreen,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan Friend QR'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                context.push('/friends/share');
              },
              icon: const Icon(Icons.qr_code),
              label: const Text('Share Your QR'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendCard(Friend friend) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () async {
          await context.push('/friends/profile/${friend.id}');
          _loadFriends();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Builder(
                    builder: (context) {
                      ImageProvider? avatarImage;
                      if (friend.profilePicPath != null &&
                          friend.profilePicPath!.isNotEmpty) {
                        try {
                          final f = File(friend.profilePicPath!);
                          if (f.existsSync()) avatarImage = FileImage(f);
                        } catch (_) {
                          avatarImage = null;
                        }
                      }

                      return CircleAvatar(
                        radius: 28,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        backgroundImage: avatarImage,
                        child: avatarImage == null
                            ? Text(
                                friend.name.isNotEmpty
                                    ? friend.name[0].toUpperCase()
                                    : '?',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                    ),
                              )
                            : null,
                      );
                    },
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              friend.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(width: 8),
                            _buildBadgesRow(friend),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _computeFriendSubtitle(friend),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              _getPrivacyIcon(friend.privacyLevel),
                              size: 16,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getPrivacyLabel(friend.privacyLevel),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                            ),
                            if (friend.isOnlineSync) ...[
                              const SizedBox(width: 8),
                              Tooltip(
                                message: 'Synced via Cloud (ChaCha20 encrypted)',
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.cloud_done,
                                      size: 14,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Synced',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () {
                      _showFriendOptions(context, friend);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        context.push('/friends/gaps/${friend.id}');
                      },
                      icon: const Icon(Icons.event_available),
                      label: const Text('Find Gaps'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await context.push('/friends/profile/${friend.id}');
                        _loadFriends();
                      },
                      icon: const Icon(Icons.person),
                      label: const Text('Profile'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFriendOptions(BuildContext context, Friend friend) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.event_available),
              title: const Text('Find Mutual Gaps'),
              onTap: () {
                Navigator.pop(context);
                context.push('/friends/gaps/${friend.id}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Profile'),
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => EditFriendBottomSheet(
                    friend: friend,
                    onSaved: () => _loadFriends(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Remove Friend'),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(friend);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(Friend friend) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Friend?'),
        content: Text('Are you sure you want to remove ${friend.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await _friendsService.deleteFriend(friend.id);
              _loadFriends();
              if (context.mounted) Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }


  IconData _getPrivacyIcon(PrivacyLevel level) {
    switch (level) {
      case PrivacyLevel.freeTimeOnly:
        return Icons.lock;
      case PrivacyLevel.busyBlocks:
        return Icons.lock_open;
      case PrivacyLevel.fullDetails:
        return Icons.visibility;
    }
  }

  String _getPrivacyLabel(PrivacyLevel level) {
    switch (level) {
      case PrivacyLevel.freeTimeOnly:
        return 'Free Time Only';
      case PrivacyLevel.busyBlocks:
        return 'Busy Blocks';
      case PrivacyLevel.fullDetails:
        return 'Full Details';
    }
  }

  Widget _buildBadgesRow(Friend friend) {
    final badges = BadgesService.instance.getBadgesFor(friend);
    if (badges.isEmpty) return const SizedBox.shrink();
    final size = Theme.of(context).textTheme.titleLarge?.fontSize ?? 20;
    return Row(
      children: badges.map((b) {
        final iconKey = (b.icon ?? '').toLowerCase();
        final icon = BadgesService.iconMap.containsKey(iconKey)
            ? BadgesService.iconMap[iconKey]!
            : Icons.label;
        return Padding(
          padding: const EdgeInsets.only(left: 3.0),
          child: FutureBuilder<File?>(
            future: BadgesService.instance.getBadgeImageFile(b),
            builder: (context, snapshot) {
              Widget content;
              if (snapshot.hasData && snapshot.data != null) {
                content = Image.file(
                  snapshot.data!,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                );
              } else {
                content = Icon(
                  icon,
                  size: size,
                  color: Theme.of(context).colorScheme.tertiary,
                );
              }

              return Tooltip(message: b.label, child: content);
            },
          ),
        );
      }).toList(),
    );
  }
}
