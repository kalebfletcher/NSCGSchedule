import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nscgschedule/friends_service.dart';
import 'package:nscgschedule/models/friend_models.dart';
import 'package:nscgschedule/models/timetable_models.dart' as models;
import 'package:nscgschedule/requests.dart';
import 'package:nscgschedule/settings.dart';
import 'package:nscgschedule/services/timetable_sync_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';

/// Screen for sharing your timetable via QR code
class ShareQRScreen extends StatefulWidget {
  const ShareQRScreen({super.key});

  @override
  State<ShareQRScreen> createState() => _ShareQRScreenState();
}

class _ShareQRScreenState extends State<ShareQRScreen> {
  final FriendsService _friendsService = GetIt.I<FriendsService>();
  final TimetableSyncService _syncService = GetIt.I<TimetableSyncService>();
  final Settings _settings = GetIt.I<Settings>();
  PrivacyLevel _selectedPrivacy = PrivacyLevel.busyBlocks;
  bool _makeOffline = false;
  String? _qrData;
  bool _isLoading = true;
  bool _isQrUpdating = false;
  bool _hasTimetable = true;
  final TextEditingController _nameController = TextEditingController();
  final GlobalKey _qrKey = GlobalKey();
  int _genToken = 0;
  bool _isGenerating = false;
  bool _needsRegenerate = false;

  @override
  void initState() {
    super.initState();
    _loadDefaultsAndGenerate();
  }

  Future<void> _loadDefaultsAndGenerate() async {
    var owner = await _settings.getKey('timetableOwner');

    if (owner.isEmpty || owner == 'My Schedule') {
      try {
        final profile = await NSCGRequests.instance.fetchUserProfile();
        if (profile['name'] != null && profile['name']!.isNotEmpty) {
          owner = profile['name']!;
        }
      } catch (_) {}
    }

    if (owner.isNotEmpty && owner != 'My Schedule') {
      _nameController.text = owner;
    } else {
      _nameController.text = 'My Schedule';
    }

    // Load saved privacy level
    final savedPrivacy = await _settings.getKey('qrPrivacyLevel');
    if (savedPrivacy.isNotEmpty) {
      switch (savedPrivacy) {
        case 'freeTimeOnly':
          _selectedPrivacy = PrivacyLevel.freeTimeOnly;
          break;
        case 'busyBlocks':
          _selectedPrivacy = PrivacyLevel.busyBlocks;
          break;
        case 'fullDetails':
          _selectedPrivacy = PrivacyLevel.fullDetails;
          break;
      }
    }

    final onlineConsent = await _syncService.isOnlineSyncEnabled();
    _makeOffline = !onlineConsent;

    await _generateQR(isInitial: true);
  }

  Future<void> _generateQR({bool isInitial = false}) async {
    // If a generation is already in progress, mark that we need a refresh
    // and return; when the in-progress generation finishes it will run
    // another generation if needed. This prevents overlapping reloads.
    if (_isGenerating) {
      _needsRegenerate = true;
      return;
    }

    _isGenerating = true;
    final int myToken = ++_genToken;
    if (isInitial && mounted) {
      setState(() => _isLoading = true);
    } else if (mounted) {
      setState(() => _isQrUpdating = true);
    }

    try {
      // Get user's name (editable field; prefills from saved timetable owner)
      final userName = _nameController.text.trim().isEmpty
          ? 'My Schedule'
          : _nameController.text.trim();

      // Persist chosen share name if it's a real name (not placeholder)
      final normalizedUserName = userName
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (normalizedUserName.isNotEmpty && normalizedUserName != 'My Schedule') {
        await _settings.setKey('timetableOwner', normalizedUserName);
      }

      // Get user's timetable
      final timetableMap = await _settings.getMap('timetable');
      if (timetableMap.isEmpty) {
        if (myToken == _genToken && mounted) {
          setState(() {
            _hasTimetable = false;
            _isLoading = false;
            _isQrUpdating = false;
          });
        }
        _isGenerating = false;
        if (_needsRegenerate) {
          _needsRegenerate = false;
          await _generateQR(isInitial: false);
        }
        return;
      }

      _hasTimetable = true;

      final timetable = models.Timetable.fromJson(
        Map<String, dynamic>.from(timetableMap),
      );

      final ownerId = await _settings.getKey('timetableOwnerId');
      final String qrData;

      if (!_makeOffline) {
        qrData = await _syncService.generateOnlineSharePayload(
          timetable: timetable,
          privacyLevel: _selectedPrivacy,
          ownerName: normalizedUserName,
          userId: ownerId.isNotEmpty ? ownerId : null,
        );
      } else {
        qrData = _friendsService.generateQRData(
          userName: normalizedUserName,
          timetable: timetable,
          privacyLevel: _selectedPrivacy,
          userId: ownerId.isNotEmpty ? ownerId : null,
        );
      }

      if (myToken == _genToken && mounted) {
        setState(() {
          _qrData = qrData;
          if (isInitial) _isLoading = false;
          _isQrUpdating = false;
        });
      }
      _isGenerating = false;
      if (_needsRegenerate) {
        _needsRegenerate = false;
        // Fire another generation to pick up the latest input
        await _generateQR(isInitial: false);
      }
    } catch (e) {
      if (myToken == _genToken && mounted) {
        setState(() {
          if (isInitial) _isLoading = false;
          _isQrUpdating = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error generating QR: $e')));
      }
      _isGenerating = false;
      if (_needsRegenerate) {
        _needsRegenerate = false;
        await _generateQR(isInitial: false);
      }
    }
  }

  Future<void> _saveQrImage() async {
    if (_qrData == null) return;

    // Generate PNG into a temporary file and share it (no persistent save)

    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        Fluttertoast.showToast(msg: 'Could not capture QR image');
        return;
      }
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        Fluttertoast.showToast(msg: 'Failed to encode image');
        return;
      }
      final tempDir = await getTemporaryDirectory();
      final file = File(
        p.join(
          tempDir.path,
          'nscg_qr_${DateTime.now().millisecondsSinceEpoch}.png',
        ),
      );
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

      // Offer share immediately
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'image/png')],
            text: 'Timetable QR Code',
          ),
        );
        if (mounted) Fluttertoast.showToast(msg: 'Shared image');
      } catch (e) {
        if (mounted) Fluttertoast.showToast(msg: 'Error sharing image: $e');
      }
    } catch (e) {
      if (mounted) Fluttertoast.showToast(msg: 'Error saving QR image: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_month,
              size: 120,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'No Timetable Available',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Sign in and fetch your timetable before you can share your schedule with friends.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.go('/timetable'),
              icon: const Icon(Icons.calendar_month),
              label: const Text('Go to Timetable'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share Your Schedule')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_hasTimetable
              ? _buildEmptyState()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Share with Friends',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                  const SizedBox(height: 8),
                  Text(
                    'Let others scan this QR code to add your schedule',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_qrData != null)
                    Column(
                      children: [
                        Container(
                          width: 280 + 48,
                          height: 280 + 48,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              RepaintBoundary(
                                key: _qrKey,
                                child: QrImageView(
                                  data: _qrData!,
                                  version: QrVersions.auto,
                                  size: 280,
                                  backgroundColor: Colors.white,
                                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                                ),
                              ),
                              if (_isQrUpdating)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.75),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: (_qrData == null || _isQrUpdating) ? null : _saveQrImage,
                              icon: const Icon(Icons.share),
                              label: const Text('Share QR Code Image'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Your name for this share',
                      hintText: 'e.g. John Doe',
                    ),
                    onChanged: (v) => _generateQR(),
                  ),
                  const SizedBox(height: 32),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Privacy Level',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          RadioGroup<PrivacyLevel>(
                            groupValue: _selectedPrivacy,
                            onChanged: (PrivacyLevel? v) async {
                              if (v == null) return;
                              setState(() => _selectedPrivacy = v);

                              // Save privacy level preference
                              final privacyStr = v == PrivacyLevel.freeTimeOnly
                                  ? 'freeTimeOnly'
                                  : v == PrivacyLevel.busyBlocks
                                  ? 'busyBlocks'
                                  : 'fullDetails';
                              await _settings.setKey(
                                'qrPrivacyLevel',
                                privacyStr,
                              );

                              _generateQR();
                            },
                            child: Column(
                              children: [
                                _buildPrivacyOption(
                                  PrivacyLevel.freeTimeOnly,
                                  'Free Time Only',
                                  'Only shows when you are available',
                                  Icons.lock,
                                ),
                                const Divider(),
                                _buildPrivacyOption(
                                  PrivacyLevel.busyBlocks,
                                  'Busy Blocks',
                                  'Shows class times but hides details',
                                  Icons.lock_open,
                                ),
                                const Divider(),
                                _buildPrivacyOption(
                                  PrivacyLevel.fullDetails,
                                  'Full Details',
                                  'Shares subjects, rooms, and times',
                                  Icons.visibility,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: SwitchListTile(
                      title: const Text('Make Offline QR Code'),
                      subtitle: Text(
                        _makeOffline
                            ? 'Generate a static offline snapshot without online sync'
                            : 'End-to-end encrypted live sync with connected friends',
                      ),
                      secondary: Icon(
                        _makeOffline ? Icons.wifi_off : Icons.cloud_sync,
                        color: !_makeOffline
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      value: _makeOffline,
                      onChanged: (bool value) async {
                        if (!value) {
                          final isOnline = await _syncService.isOnlineSyncEnabled();
                          if (!isOnline) {
                            if (context.mounted) {
                              final accepted = await context.push('/friends/privacy-policy');
                              final nowOnline = await _syncService.isOnlineSyncEnabled();
                              if (accepted != true && !nowOnline) {
                                return;
                              }
                            } else {
                              return;
                            }
                          }
                        }
                        setState(() => _makeOffline = value);
                        _generateQR();
                      },
                    ),
                  ),
                  if (!_makeOffline)
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 0),
                      child: ListTile(
                        leading: const Icon(Icons.manage_accounts),
                        title: const Text('Manage Access'),
                        subtitle: const Text('View connected devices, revoke or block'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/friends/sync-access'),
                      ),
                    ),
                  const SizedBox(height: 24),
                  _buildInfoCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildPrivacyOption(
    PrivacyLevel level,
    String title,
    String description,
    IconData icon,
  ) {
    final isSelected = _selectedPrivacy == level;
    return RadioListTile<PrivacyLevel>(
      value: level,
      title: Row(
        children: [Icon(icon, size: 20), const SizedBox(width: 8), Text(title)],
      ),
      subtitle: Text(description),
      selected: isSelected,
    );
  }

  Widget _buildInfoCard() {
    final isSync = !_makeOffline;
    return Card(
      color: isSync
          ? Theme.of(context).colorScheme.tertiaryContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              isSync ? Icons.lock_clock : Icons.info_outline,
              color: isSync
                  ? Theme.of(context).colorScheme.onTertiaryContainer
                  : Theme.of(context).colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isSync
                    ? 'Encrypted with ChaCha20-Poly1305. Only friends with this QR code hold the decryption key. Schedule updates sync automatically.'
                    : 'This offline QR code is generated locally and doesn\'t store any data online. Your schedule stays on your device.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isSync
                      ? Theme.of(context).colorScheme.onTertiaryContainer
                      : Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Screen for scanning a friend's QR code
class ScanQRScreen extends StatefulWidget {
  const ScanQRScreen({super.key});

  @override
  State<ScanQRScreen> createState() => _ScanQRScreenState();
}

class _ScanQRScreenState extends State<ScanQRScreen> {
  final FriendsService _friendsService = GetIt.I<FriendsService>();
  final TimetableSyncService _syncService = GetIt.I<TimetableSyncService>();
  MobileScannerController? _controller;
  bool _isProcessing = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<bool> _processScannedData(String raw) async {
    // 1. Check if this is an online sync QR code
    if (_syncService.isOnlineSyncQR(raw)) {
      final isOnline = await _syncService.isOnlineSyncEnabled();
      if (!isOnline) {
        if (mounted) {
          final shouldEnable = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Online Sync Required'),
              content: const Text(
                'This QR code uses online synchronization. To use this QR code, you need to enable online sync and accept the Privacy Policy & Terms. \n Alternatively, you can request them to generate you an offline QR Code.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('View Privacy & Terms'),
                ),
              ],
            ),
          );

          if (shouldEnable == true && mounted) {
            final accepted = await context.push('/friends/privacy-policy');
            final nowOnline = await _syncService.isOnlineSyncEnabled();
            if (accepted != true && !nowOnline) {
              return false;
            }
          } else {
            return false;
          }
        }
      }

      try {
        if (mounted) {
          Fluttertoast.showToast(msg: 'Connecting to sync server...');
        }
        final friend = await _syncService.claimAndAddFriendFromQR(raw);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${friend.name} added with live online sync!'),
            ),
          );
          context.pop();
        }
        return true;
      } on InvalidInviteKeyException catch (e) {
        if (mounted) {
          await _showInvalidInviteDialog(ownerName: e.ownerName);
        }
        return false;
      } on TimetableNotFoundException catch (e) {
        if (mounted) {
          await _showTimetableNotFoundDialog(e.ownerName);
        }
        return false;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to claim online sync: $e')),
          );
        }
        return false;
      }
    }

    // 2. Standard offline QR code parsing
    final friend = _friendsService.parseQRData(raw);
    if (friend == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid QR code')));
      }
      return false;
    }

    var friendToSave = friend;

    // Auto-replace by stable userId when available
    if (friendToSave.userId != null && friendToSave.userId!.isNotEmpty) {
      final matches = _friendsService
          .getAllFriends()
          .where((f) => f.userId != null && f.userId == friendToSave.userId)
          .toList();
      if (matches.isNotEmpty) {
        final existingByUserId = matches.first;
        // Preserve any locally-set profile picture when replacing the entry
        final replaced = friendToSave.copyWith(
          id: existingByUserId.id,
          addedAt: DateTime.now(),
          profilePicPath: existingByUserId.profilePicPath,
        );
        await _friendsService.saveFriend(replaced);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${replaced.name} (updated)')),
          );
          context.pop();
          return true;
        }
      }
    }

    // Check exact share id collision as a fallback
    final existing = _friendsService.getFriend(friend.id);
    if (existing != null) {
      if (mounted) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Friend Already Added'),
            content: Text(
              '${friend.name} is already in your friends list. Replace with updated data?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Replace'),
              ),
            ],
          ),
        );

        if (replace != true) {
          return false;
        }
        // Preserve locally-set profile picture when replacing by share id
        final preserved = friendToSave.copyWith(
          id: existing.id,
          addedAt: DateTime.now(),
          profilePicPath: existing.profilePicPath,
        );
        friendToSave = preserved;
      }
    }

    // Save friend
    await _friendsService.saveFriend(friendToSave);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${friendToSave.name} added successfully!')),
      );
      context.pop();
    }
    return true;
  }

  Future<void> _showInvalidInviteDialog({
    required String ownerName,
  }) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withValues(alpha: 0.8),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.key_off_rounded,
            size: 28,
            color: colorScheme.onErrorContainer,
          ),
        ),
        title: Text(
          'Invite Key Invalidated',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'The invite QR code for $ownerName is no longer valid.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'The owner may have regenerated their invite keys or shared an older QR code. Please ask $ownerName to share their newest QR code with you.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(120, 42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTimetableNotFoundDialog(String ownerName) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer.withValues(alpha: 0.8),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.cloud_off_rounded,
            size: 28,
            color: colorScheme.onSecondaryContainer,
          ),
        ),
        title: Text(
          'Timetable Not Found',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'The timetable for $ownerName could not be found on the server. They may have removed or re-published their schedule.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(120, 42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    setState(() => _isProcessing = true);

    try {
      await _processScannedData(barcode.rawValue!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _scanFromImage() async {
    if (_isProcessing) return;
    if (!await _ensureImagePermissionForScan()) return;

    try {
      final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      setState(() => _isProcessing = true);

      final dynamic result = await _controller?.analyzeImage(file.path);

      List<Barcode>? barcodes;
      if (result == null) {
        barcodes = null;
      } else if (result is BarcodeCapture) {
        barcodes = result.barcodes;
      } else if (result is List) {
        barcodes = List<Barcode>.from(result.whereType<Barcode>());
      } else if (result is Barcode) {
        barcodes = [result];
      }

      if (barcodes == null || barcodes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No QR code found in image')),
          );
        }
        setState(() => _isProcessing = false);
        return;
      }

      final barcode = barcodes.first;
      final raw = barcode.rawValue;
      if (raw == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No QR code found in image')),
          );
        }
        setState(() => _isProcessing = false);
        return;
      }

      await _processScannedData(raw);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error scanning image: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<bool> _ensureImagePermissionForScan() async {
    try {
      if (Platform.isAndroid) {
        final photos = await Permission.photos.status;
        if (photos.isGranted) return true;
        final req = await Permission.photos.request();
        if (req.isGranted) return true;
        final storage = await Permission.storage.request();
        if (storage.isGranted) return true;
        if (storage.isPermanentlyDenied && context.mounted ||
            req.isPermanentlyDenied && context.mounted) {
          final open = await showDialog<bool>(
            // ignore: use_build_context_synchronously
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Permission required'),
              content: const Text(
                'Please grant photo permission in app settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
          if (open == true) await openAppSettings();
        }
        return false;
      } else if (Platform.isIOS) {
        final photos = await Permission.photos.status;
        if (photos.isGranted) return true;
        final req = await Permission.photos.request();
        if (req.isGranted) return true;
        if (req.isPermanentlyDenied && context.mounted) {
          final open = await showDialog<bool>(
            // ignore: use_build_context_synchronously
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Permission required'),
              content: const Text('Please grant photo permission in Settings.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
          if (open == true) await openAppSettings();
        }
        return false;
      }
    } catch (_) {
      final s = await Permission.storage.request();
      return s.isGranted;
    }
    return true;
  }

  // Removed interactive naming prompt: renaming is available via friend profile/menu.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Friend QR')),
      body: Stack(
        children: [
          if (_controller != null)
            MobileScanner(
              controller: _controller!,
              onDetect: _handleBarcode,
              errorBuilder: (context, error) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.videocam_off_outlined,
                          size: 56,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Camera unavailable or permission denied',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You can still select a QR code from your photo library below, or grant camera permission in Settings.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => openAppSettings(),
                          icon: const Icon(Icons.settings, size: 18),
                          label: const Text('Open Settings'),
                        ),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                );
              },
            ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 4, right: 8),
                        child: Icon(
                          Icons.qr_code_scanner,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Position the QR code within the frame',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'It will scan the code automatically',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _scanFromImage,
                    icon: const Icon(Icons.photo_library, size: 18),
                    label: const Text('Select from library'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
