import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nscgschedule/models/timetable_models.dart' as models;
import 'package:nscgschedule/services/timetable_sync_service.dart';
import 'package:nscgschedule/settings.dart';

class PrivacyPolicyScreen extends StatefulWidget {
  final bool isReviewOnly;
  final VoidCallback? onAccepted;

  const PrivacyPolicyScreen({
    super.key,
    this.isReviewOnly = false,
    this.onAccepted,
  });

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  final TimetableSyncService _syncService = GetIt.I<TimetableSyncService>();

  bool _isLoading = true;
  bool _isFetchingLatest = false;
  String? _errorMessage;
  String _markdownContent = '';
  bool _acknowledged = false;
  bool _isSubmitting = false;
  bool _isPolicyAccepted = false;

  @override
  void initState() {
    super.initState();
    _loadPolicy();
  }

  Future<void> _loadPolicy() async {
    // Show cached version immediately if available
    final cachedPolicy = await _syncService.getCachedPrivacyPolicy();
    final alreadyAccepted = await _syncService.isPrivacyPolicyAccepted();

    if (mounted) {
      setState(() {
        if (cachedPolicy != null && cachedPolicy.isNotEmpty) {
          _markdownContent = cachedPolicy;
          _isLoading = false;
        } else {
          _isLoading = true;
        }
        _isPolicyAccepted = alreadyAccepted;
        _acknowledged = alreadyAccepted;
        _errorMessage = null;
        _isFetchingLatest = true;
      });
    }

    try {
      final markdown = await _syncService.fetchPrivacyPolicy();
      if (mounted) {
        final currentAccepted = await _syncService.isPrivacyPolicyAccepted();
        setState(() {
          _markdownContent = markdown;
          _isPolicyAccepted = currentAccepted;
          _isLoading = false;
          _isFetchingLatest = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFetchingLatest = false;
          if (_markdownContent.isEmpty) {
            _errorMessage = e.toString();
            _isLoading = false;
          }
        });
      }
    }
  }

  Future<void> _handleAccept() async {
    if (!_acknowledged || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      await _syncService.setPrivacyPolicyAccepted(true);
      await _syncService.setOnlineSyncEnabled(true);
      await _syncService.setFriendsOnboardingCompleted(true);

      // Attempt initial timetable publish in background if user has schedule
      try {
        final ttMap = await settings.getMap('timetable');
        if (ttMap.isNotEmpty) {
          final tt = models.Timetable.fromJson(Map<String, dynamic>.from(ttMap));
          await _syncService.publishTimetable(timetable: tt);
        }
      } catch (_) {}

      if (widget.onAccepted != null) {
        widget.onAccepted!();
      } else if (mounted) {
        if (context.canPop()) {
          context.pop(true);
        } else {
          context.go('/friends');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to enable sync: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Online Sync Privacy & Terms'),
        actions: [
          if (_isFetchingLatest && !_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.0),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload Policy',
            onPressed: (_isLoading || _isFetchingLatest) ? null : _loadPolicy,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Fetching latest privacy & terms…'),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 64,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Unable to Load Privacy & Terms',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please check your internet connection or server address in Settings.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _loadPolicy,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: Markdown(
                        data: _markdownContent,
                        padding: const EdgeInsets.all(20.0),
                        selectable: true,
                        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                          h1: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                          h2: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          h3: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.secondary,
                          ),
                          p: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.5,
                          ),
                          listBullet: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                    if (!_isPolicyAccepted) ...[
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          border: Border(
                            top: BorderSide(
                              color: theme.dividerColor.withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CheckboxListTile(
                                value: _acknowledged,
                                onChanged: _isSubmitting
                                    ? null
                                    : (val) => setState(() => _acknowledged = val ?? false),
                                contentPadding: EdgeInsets.zero,
                                controlAffinity: ListTileControlAffinity.leading,
                                title: Text(
                                  'I acknowledge and agree to the Privacy Policy & Terms and understand how my data is stored and encrypted.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: FilledButton(
                                  onPressed: (_acknowledged && !_isSubmitting)
                                      ? _handleAccept
                                      : null,
                                  child: _isSubmitting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Acknowledge & Enable Online Sync',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}
