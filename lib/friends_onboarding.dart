import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nscgschedule/services/timetable_sync_service.dart';

class FriendsOnboardingScreen extends StatelessWidget {
  final VoidCallback? onContinueOffline;
  final VoidCallback? onEnableOnlineSync;

  const FriendsOnboardingScreen({
    super.key,
    this.onContinueOffline,
    this.onEnableOnlineSync,
  });

  Future<void> _handleContinueOffline(BuildContext context) async {
    final theme = Theme.of(context);
    final confirmOffline = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.cloud_off_outlined,
          size: 36,
          color: theme.colorScheme.primary,
        ),
        title: const Text('Continue in Offline Mode?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'In offline mode, you cannot join live sync or receive automatic schedule updates from friends.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You can still share and scan offline QR codes directly.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Friends using Online Sync can still scan your offline QR code to import your schedule.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You can enable Online Sync at any time in Settings.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue Offline'),
          ),
        ],
      ),
    );

    if (confirmOffline != true) return;

    final syncService = GetIt.I<TimetableSyncService>();
    await syncService.setFriendsOnboardingCompleted(true);
    await syncService.setOnlineSyncEnabled(false);
    await syncService.setPrivacyPolicyAccepted(false);

    if (onContinueOffline != null) {
      onContinueOffline!();
    } else if (context.mounted) {
      context.go('/friends');
    }
  }

  void _handleEnableOnlineSync(BuildContext context) {
    if (onEnableOnlineSync != null) {
      onEnableOnlineSync!();
    } else {
      context.push('/friends/privacy-policy');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends & Sharing'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                children: [
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.groups_rounded,
                        size: 44,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Stay Connected With Friends',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Compare timetables, find mutual free periods, and keep your schedules synchronized.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 28),
                  _buildFeatureCard(
                    context,
                    icon: Icons.schedule_rounded,
                    iconColor: theme.colorScheme.primary,
                    title: 'Find Mutual Free Gaps',
                    subtitle:
                        'Quickly identify overlapping free periods between you and your friends for lunch or study sessions.',
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureCard(
                    context,
                    icon: Icons.lock_outline_rounded,
                    iconColor: theme.colorScheme.tertiary,
                    title: 'End-to-End Encrypted',
                    subtitle:
                        'Your schedule is encrypted directly on your device (ChaCha20-Poly1305). The server never has access to your decryption keys.',
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureCard(
                    context,
                    icon: Icons.security_rounded,
                    iconColor: theme.colorScheme.secondary,
                    title: 'Granular Privacy Tiers',
                    subtitle:
                        'Control what each friend sees: Full timetable details, Busy blocks only, or Free time only.',
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureCard(
                    context,
                    icon: Icons.cloud_sync_outlined,
                    iconColor: theme.colorScheme.primary,
                    title: 'Real-Time Online Updates',
                    subtitle:
                        'Changes to classes and room locations sync automatically across devices without re-scanning QR codes.',
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureCard(
                    context,
                    icon: Icons.qr_code_2_rounded,
                    iconColor: theme.colorScheme.outline,
                    title: 'Offline-First & Local QR Ready',
                    subtitle:
                        'No internet required if you prefer to share and view schedules entirely offline using local QR codes.',
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                border: Border(
                  top: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.15),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: () => _handleEnableOnlineSync(context),
                      icon: const Icon(Icons.cloud_sync_outlined),
                      label: const Text(
                        'Enable Online Sync (Recommended)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: () => _handleContinueOffline(context),
                      icon: const Icon(Icons.cloud_off_outlined),
                      label: const Text(
                        'Continue Offline',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 24,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
