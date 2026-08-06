import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nscgschedule/friends_service.dart';
import 'package:nscgschedule/models/friend_models.dart';
import 'package:nscgschedule/models/timetable_models.dart' as models;
import 'package:nscgschedule/settings.dart';

class GapsFinderScreen extends StatefulWidget {
  final String friendId;

  const GapsFinderScreen({super.key, required this.friendId});

  @override
  State<GapsFinderScreen> createState() => _GapsFinderScreenState();
}

class _GapsFinderScreenState extends State<GapsFinderScreen> {
  final FriendsService _friendsService = GetIt.I<FriendsService>();
  final Settings _settings = GetIt.I<Settings>();

  Friend? _friend;
  List<MutualGap> _gaps = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load friend
      final friend = _friendsService.getFriend(widget.friendId);
      if (friend == null) {
        setState(() {
          _error = 'Friend not found';
          _isLoading = false;
        });
        return;
      }

      // Load user's timetable
      final timetableMap = await _settings.getMap('timetable');
      if (timetableMap.isEmpty) {
        setState(() {
          _error = 'Your timetable is not loaded';
          _isLoading = false;
        });
        return;
      }

      final userTimetable = models.Timetable.fromJson(
        Map<String, dynamic>.from(timetableMap),
      );

      // Find mutual gaps
      final gaps = _friendsService.findMutualGaps(
        userTimetable: userTimetable,
        friend: friend,
      );

      setState(() {
        _friend = friend;
        _gaps = gaps;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _friend != null ? 'Gaps with ${_friend!.name}' : 'Finding Gaps',
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError()
          : _gaps.isEmpty
          ? _buildNoGaps()
          : _buildGapsList(),
    );
  }

  Widget _buildError() {
    final isMissingTimetable =
        _error?.contains('timetable is not loaded') ?? false;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isMissingTimetable ? Icons.calendar_month : Icons.error_outline,
              size: 120,
              color: isMissingTimetable
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                  : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              isMissingTimetable
                  ? 'No Timetable Available'
                  : 'Something Went Wrong',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 32),
            if (isMissingTimetable)
              FilledButton.icon(
                onPressed: () => context.go('/timetable'),
                icon: const Icon(Icons.calendar_month),
                label: const Text('Go to Timetable'),
              )
            else
              FilledButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoGaps() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_busy,
              size: 120,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'No Mutual Free Time',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'You and ${_friend?.name} don\'t have any overlapping free periods this week.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Profile'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGapsList() {
    // Group gaps by day
    final gapsByDay = <String, List<MutualGap>>{};
    for (final gap in _gaps) {
      gapsByDay.putIfAbsent(gap.weekday, () => []).add(gap);
    }

    // Order days
    final orderedDays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
    ];
    final sortedDays = orderedDays
        .where((day) => gapsByDay.containsKey(day))
        .toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedDays.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildSummaryCard();
        }
        final day = sortedDays[index - 1];
        final dayGaps = gapsByDay[day]!;
        return _buildDayCard(day, dayGaps);
      },
    );
  }

  Widget _buildSummaryCard() {
    final totalMinutes = _gaps.fold<int>(
      0,
      (sum, gap) => sum + gap.duration.inMinutes,
    );
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    return Card(
      margin: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Icon(
                    Icons.event_available,
                    color: Theme.of(context).colorScheme.onPrimary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_gaps.length} Mutual Free Period${_gaps.length != 1 ? 's' : ''}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hours > 0
                            ? '$hours hour${hours != 1 ? 's' : ''} $minutes min total'
                            : '$minutes minutes total',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer
                              .withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Perfect times to hang out with ${_friend?.name}!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCard(String day, List<MutualGap> gaps) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  day,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...gaps.map((gap) => _buildGapItem(gap)),
          ],
        ),
      ),
    );
  }

  Widget _buildGapItem(MutualGap gap) {
    final hours = gap.duration.inHours;
    final minutes = gap.duration.inMinutes % 60;
    final durationText = hours > 0 ? '${hours}h ${minutes}m' : '$minutes min';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.access_time,
              size: 20,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${gap.startTime} - ${gap.endTime}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  durationText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.check_circle,
            color: Theme.of(context).colorScheme.primary,
            size: 24,
          ),
        ],
      ),
    );
  }
}
