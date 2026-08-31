import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nscgschedule/friends_service.dart';
import 'package:nscgschedule/models/friend_models.dart';
import 'package:nscgschedule/edit_friend_bottom_sheet.dart';
import 'package:intl/intl.dart';
import 'package:nscgschedule/badges_service.dart';
import 'dart:io';
import 'dart:async';
import 'package:nscgschedule/debug_service.dart';
import 'package:nscgschedule/services/timetable_sync_service.dart';

class FriendProfileScreen extends StatefulWidget {
  final String friendId;

  const FriendProfileScreen({super.key, required this.friendId});

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  final FriendsService _friendsService = GetIt.I<FriendsService>();
  final TimetableSyncService _syncService = GetIt.I<TimetableSyncService>();
  Friend? _friend;
  bool _isLoading = true;
  bool _isSyncing = false;
  Timer? _refreshTimer;
  final DebugService _debug = GetIt.I<DebugService>();

  @override
  void initState() {
    super.initState();
    _loadFriend();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _loadFriend() {
    setState(() => _isLoading = true);
    final friend = _friendsService.getFriend(widget.friendId);
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
    setState(() {
      _friend = friend;
      _isLoading = false;
    });
  }

  Future<void> _syncFriendNow() async {
    if (_friend == null || !_friend!.isOnlineSync || _isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      await _syncService.syncFriend(_friend!);
      if (mounted) {
        _loadFriend();
      }
    } catch (_) {
      // Handled silently
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Friend Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_friend == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Friend Profile')),
        body: const Center(child: Text('Friend not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_friend!.name),
        actions: [
          if (_friend!.isOnlineSync)
            IconButton(
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              tooltip: 'Sync Now',
              onPressed: _isSyncing ? null : _syncFriendNow,
            ),
          IconButton(icon: const Icon(Icons.delete), onPressed: _confirmDelete),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _friend!.isOnlineSync ? _syncFriendNow : () async {},
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              _buildActions(),
              const SizedBox(height: 4),
              _buildSchedulePreview(),
              if (_friend!.timetable.exams != null && _friend!.timetable.exams!.isNotEmpty)
                _buildExamPreview(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundImage:
                _friend!.profilePicPath != null &&
                    _friend!.profilePicPath!.isNotEmpty
                ? FileImage(File(_friend!.profilePicPath!))
                : null,
            child:
                _friend!.profilePicPath == null ||
                    _friend!.profilePicPath!.isEmpty
                ? Text(
                    _friend!.name.isNotEmpty
                        ? _friend!.name[0].toUpperCase()
                        : '?',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _friend!.name,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 8),
              _buildBadgesRow(_friend!),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _getPrivacyIcon(_friend!.privacyLevel),
                size: 18,
                color: Theme.of(
                  context,
                ).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Text(
                _getPrivacyLabel(_friend!.privacyLevel),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                ),
              ),
              if (_friend!.isOnlineSync) ...[
                const SizedBox(width: 10),
                Icon(
                  Icons.cloud_done,
                  size: 16,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 4),
                Text(
                  'Cloud Synced',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _friend!.isOnlineSync && _friend!.lastSyncedAt != null
                ? 'Added ${_formatShortDate(_friend!.addedAt)} • Synced ${_formatShortSyncTime(_friend!.lastSyncedAt!)}'
                : 'Added ${_formatShortDate(_friend!.addedAt)}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  String _formatShortSyncTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.isNegative || diff.inMinutes < 1) {
      return 'just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return DateFormat.jm().format(dt);
    } else if (now.difference(DateTime(dt.year, dt.month, dt.day)).inDays == 1) {
      return 'yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else if (dt.year == now.year) {
      return DateFormat.MMMd().format(dt);
    } else {
      return DateFormat.yMMMd().format(dt);
    }
  }

  String _formatShortDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year) {
      return DateFormat.MMMd().format(dt);
    }
    return DateFormat.yMMMd().format(dt);
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () {
                context.push('/friends/gaps/${_friend!.id}');
              },
              icon: const Icon(Icons.event_available),
              label: const Text('Find Gaps'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _editProfile,
              icon: const Icon(Icons.edit),
              label: const Text('Edit Profile'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchedulePreview() {
    final totalLessons = _friend!.timetable.days.fold<int>(
      0,
      (sum, d) => sum + d.lessons.length,
    );

    if (totalLessons == 0) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_month,
                size: 100,
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 20),
              Text(
                'No Timetable Available',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                _friend!.isOnlineSync
                    ? '${_friend!.name}\'s timetable hasn\'t been synced yet or has no scheduled classes.'
                    : '${_friend!.name} doesn\'t have any classes in their timetable.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              if (_friend!.isOnlineSync) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isSyncing ? null : _syncFriendNow,
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: const Text('Sync Timetable'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Weekly Schedule',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_friend!.timetable.days.fold<int>(0, (sum, d) => sum + d.lessons.length)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            children: _friend!.timetable.days
                .map((day) => _buildDayRow(day))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDayRow(FriendDaySchedule day) {
    final accent = Theme.of(context).colorScheme.primary;
    final now = _debug.enabled ? _debug.now : DateTime.now();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          DateFormat.EEEE().format(now) == day.weekday
                              ? '• ${day.weekday}'
                              : day.weekday,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color:
                                    DateFormat.EEEE().format(now) == day.weekday
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      day.lessons.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Text(
                                'No classes',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withAlpha(0x88),
                                    ),
                              ),
                            )
                          : Column(
                              children: day.lessons.map((lesson) {
                                // determine if this lesson is the current lesson (uses debug-aware `now` from outer scope)
                                bool isCurrent = false;
                                final todayName = DateFormat.EEEE().format(now);
                                if (todayName == day.weekday) {
                                  try {
                                    final start = DateFormat.Hm().parse(
                                      lesson.startTime,
                                    );
                                    final end = DateFormat.Hm().parse(
                                      lesson.endTime,
                                    );
                                    final startToday = DateTime(
                                      now.year,
                                      now.month,
                                      now.day,
                                      start.hour,
                                      start.minute,
                                    );
                                    final endToday = DateTime(
                                      now.year,
                                      now.month,
                                      now.day,
                                      end.hour,
                                      end.minute,
                                    );
                                    isCurrent =
                                        (now.isAfter(startToday) &&
                                            now.isBefore(endToday)) ||
                                        now.isAtSameMomentAs(startToday) ||
                                        now.isAtSameMomentAs(endToday);
                                  } catch (e) {
                                    isCurrent = false;
                                  }
                                } else {
                                  isCurrent = false;
                                }

                                final sideColor = isCurrent
                                    ? Theme.of(context).colorScheme.secondary
                                    : accent;

                                return Card(
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          left: BorderSide(
                                            color: sideColor,
                                            width: 4,
                                          ),
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    lesson.name ?? 'Busy',
                                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.schedule,
                                                  size: 16,
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '${lesson.startTime} - ${lesson.endTime}',
                                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                      ),
                                                ),
                                                if (lesson.room != null && lesson.room!.isNotEmpty) ...[
                                                  const Spacer(),
                                                  Icon(
                                                    Icons.room,
                                                    size: 16,
                                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    lesson.room!,
                                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                  ),
                                                ]
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExamPreview() {
    final exams = _friend!.timetable.exams!;
    
    // Sort exams by date if possible
    // Note: dates are formatted like "04-11-2025" (dd-mm-yyyy)
    final sortedExams = List<FriendExam>.from(exams)..sort((a, b) {
      DateTime? parseDate(String d) {
        try {
          final p = d.split('-');
          return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
        } catch (_) { return null; }
      }
      final da = parseDate(a.date);
      final db = parseDate(b.date);
      if (da == null || db == null) return 0;
      return da.compareTo(db);
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.assignment,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Upcoming Exams',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${exams.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...sortedExams.map((exam) {
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              margin: const EdgeInsets.only(bottom: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 4,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                exam.subjectDescription,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                exam.date,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondaryContainer,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 16,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${exam.startTime} - ${exam.finishTime}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.room,
                              size: 16,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              exam.examRoom,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _editProfile() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => EditFriendBottomSheet(
        friend: _friend!,
        onSaved: () => _loadFriend(),
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Friend?'),
        content: Text('Are you sure you want to remove ${_friend!.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await _friendsService.deleteFriend(_friend!.id);
              if (context.mounted) {
                Navigator.pop(context); // Close dialog
                context.pop(); // Go back to friends list
              }
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
    final size = Theme.of(context).textTheme.headlineMedium?.fontSize ?? 24;
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
