import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nscgschedule/services/timetable_sync_service.dart';
import 'package:nscgschedule/friends_service.dart';
import 'package:nscgschedule/badges_service.dart';
import 'package:nscgschedule/models/friend_models.dart';
import 'package:nscgschedule/edit_friend_bottom_sheet.dart';
import 'dart:io';

class TimetableAccessListScreen extends StatefulWidget {
  const TimetableAccessListScreen({super.key});

  @override
  State<TimetableAccessListScreen> createState() =>
      _TimetableAccessListScreenState();
}

class _TimetableAccessListScreenState
    extends State<TimetableAccessListScreen> {
  final _syncService = GetIt.I<TimetableSyncService>();
  final _friendsService = GetIt.I<FriendsService>();

  bool _isLoading = true;
  String? _error;
  TimetableAccessInfo? _accessInfo;
  List<Friend> _friends = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _syncService.checkAndSyncMailbox();
      _friends = _friendsService.getAllFriends(includeHidden: true);
      
      final info = await _syncService.fetchAccessList();
      
      setState(() {
        _accessInfo = info;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Friend? _getFriendForAccessCode(String code) {
    return _friends.where((f) => f.grantedAccessCode == code || f.syncAccessCode == code).firstOrNull;
  }

  Future<void> _confirmAndRemove(ActiveAccessEntry entry) async {
    final friend = _getFriendForAccessCode(entry.accessCode);
    final name = friend?.name ?? 'this device';
    final confirmed = await _showConfirmDialog(
      title: 'Remove Access',
      content:
          'Remove access for $name? They will lose access immediately but can re-scan your QR code.',
      destructiveLabel: 'Remove',
    );
    if (!confirmed) return;
    try {
      await _syncService.removeDeviceAccess(entry.accessCode);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to remove access')),
        );
      }
    }
  }

  Future<void> _confirmAndBlock(ActiveAccessEntry entry) async {
    final friend = _getFriendForAccessCode(entry.accessCode);
    final name = friend?.name ?? 'this device';
    final confirmed = await _showConfirmDialog(
      title: 'Block Device',
      content:
          'Block $name permanently? They cannot re-add themselves until you unblock them.',
      destructiveLabel: 'Block',
    );
    if (!confirmed) return;
    try {
      await _syncService.blockDevice(entry.accessCode);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to block device')),
        );
      }
    }
  }

  Future<void> _confirmAndUnblock(BlockedAccessEntry entry) async {
    final friend = _getFriendForAccessCode(entry.accessCode);
    final name = friend?.name ?? entry.name ?? 'this device';
    final confirmed = await _showConfirmDialog(
      title: 'Unblock Device',
      content: 'Allow $name to re-register with your timetable?',
      destructiveLabel: 'Unblock',
    );
    if (!confirmed) return;
    try {
      await _syncService.unblockDevice(entry.accessCode);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to unblock device')),
        );
      }
    }
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String content,
    required String destructiveLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(destructiveLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _getPermissionLabel(String level) {
    return switch (level) {
      'all' => 'Full Details',
      'busy' => 'Busy Blocks',
      'free' => 'Free Time Only',
      _ => level,
    };
  }


  Widget _buildActiveCard(ActiveAccessEntry entry) {
    final friend = _getFriendForAccessCode(entry.accessCode);
    final displayName = friend?.name ?? (entry.hasEncryptedName ? '(decrypting…)' : 'Unknown device');
    final addedDate = '${entry.createdAt.day}/${entry.createdAt.month}/${entry.createdAt.year}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    if (friend != null && friend.profilePicPath != null && friend.profilePicPath!.isNotEmpty) {
                      try {
                        final f = File(friend.profilePicPath!);
                        if (f.existsSync()) avatarImage = FileImage(f);
                      } catch (_) {
                        avatarImage = null;
                      }
                    }

                    return CircleAvatar(
                      radius: 28,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      backgroundImage: avatarImage,
                      child: avatarImage == null
                          ? Text(
                              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                          Flexible(
                            child: Text(
                              displayName,
                              style: Theme.of(context).textTheme.titleLarge,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (friend != null) ...[
                            const SizedBox(width: 8),
                            _buildBadgesRow(friend),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Added $addedDate · ${_getPermissionLabel(entry.permissionLevel)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                      ),
                    ],
                  ),
                ),
                if (friend != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit Profile',
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (context) => EditFriendBottomSheet(
                          friend: friend,
                          onSaved: () => _load(),
                        ),
                      );
                    },
                  )
                else
                  const SizedBox(width: 48), // Padding equivalent to icon button
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmAndRemove(entry),
                    icon: const Icon(Icons.link_off),
                    label: const Text('Remove'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.errorContainer,
                      foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    onPressed: () => _confirmAndBlock(entry),
                    icon: const Icon(Icons.block),
                    label: const Text('Block'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedCard(BlockedAccessEntry entry) {
    final friend = _getFriendForAccessCode(entry.accessCode);
    final displayName = friend?.name ??
        entry.name ??
        (entry.hasEncryptedName ? '(decrypting…)' : 'Blocked Device');
    final blockedDate =
        '${entry.createdAt.day}/${entry.createdAt.month}/${entry.createdAt.year}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.5),
      child: ListTile(
        leading: Builder(
          builder: (context) {
            ImageProvider? avatarImage;
            if (friend != null &&
                friend.profilePicPath != null &&
                friend.profilePicPath!.isNotEmpty) {
              try {
                final f = File(friend.profilePicPath!);
                if (f.existsSync()) avatarImage = FileImage(f);
              } catch (_) {
                avatarImage = null;
              }
            }

            return Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor:
                      Theme.of(context).colorScheme.errorContainer,
                  backgroundImage: avatarImage,
                  child: avatarImage == null
                      ? Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.block,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                displayName,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (friend != null) ...[
              const SizedBox(width: 8),
              _buildBadgesRow(friend),
            ],
          ],
        ),
        subtitle: Text(
          'Blocked on $blockedDate',
          style: TextStyle(
            color: Theme.of(context)
                .colorScheme
                .onErrorContainer
                .withValues(alpha: 0.8),
          ),
        ),
        trailing: OutlinedButton(
          onPressed: () => _confirmAndUnblock(entry),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
            side: BorderSide(color: Theme.of(context).colorScheme.error),
          ),
          child: const Text('Unblock'),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.devices_outlined,
              size: 120,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'No Connected Devices',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Share your timetable QR code with friends to let them sync and compare schedules with you.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                context.push('/friends/share');
              },
              icon: const Icon(Icons.qr_code),
              label: const Text('Share Your QR'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Access Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh Access List',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 80,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Something Went Wrong',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 32),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _accessInfo == null ||
                      (_accessInfo!.active.isEmpty &&
                          _accessInfo!.blocked.isEmpty)
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        children: [
                          if (_accessInfo!.active.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text(
                                'Active Devices',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            ..._accessInfo!.active
                                .map((e) => _buildActiveCard(e)),
                          ],
                          if (_accessInfo!.blocked.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                              child: Text(
                                'Blocked Devices',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            ..._accessInfo!.blocked
                                .map((e) => _buildBlockedCard(e)),
                          ],
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildBadgesRow(Friend friend) {
    final badges = BadgesService.instance.getBadgesFor(friend);
    if (badges.isEmpty) return const SizedBox.shrink();
    final size = Theme.of(context).textTheme.titleLarge?.fontSize ?? 20;
    return Row(
      mainAxisSize: MainAxisSize.min,
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

