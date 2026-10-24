import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'attendance_controller.dart';
import 'attendance_repository.dart';

/// "매일매일 출석체크" popup. Closing it never records attendance; only the
/// stamp button does (server-side, once per KST day).
Future<void> showAttendanceDialog(
  BuildContext context,
  AttendanceController controller,
) => showDialog<void>(
  context: context,
  builder: (_) => AttendanceDialog(controller: controller),
);

class AttendanceDialog extends StatefulWidget {
  const AttendanceDialog({super.key, required this.controller});
  final AttendanceController controller;

  @override
  State<AttendanceDialog> createState() => _AttendanceDialogState();
}

class _AttendanceDialogState extends State<AttendanceDialog> {
  AttendanceController get controller => widget.controller;
  DateTime? _month;
  Future<List<AttendanceDay>>? _days;
  bool _busy = false;
  bool _loadingStatus = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    if (controller.status == null) {
      _reloadStatus();
    } else {
      _showMonth(controller.status!.today);
    }
  }

  Future<void> _reloadStatus() async {
    setState(() => _loadingStatus = true);
    final status = await controller.refresh();
    if (!mounted) return;
    setState(() => _loadingStatus = false);
    if (status != null) _showMonth(_month ?? status.today);
  }

  void _showMonth(DateTime month) {
    setState(() {
      _month = DateTime(month.year, month.month);
      _days = controller.repository.month(_month!);
    });
  }

  Future<void> _stamp() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await controller.checkIn();
      _message = result.already
          ? '오늘 출석은 이미 완료됐어요.'
          : attendanceRewardMessage(result.status.streak, result.points ?? 1);
      _messageIsError = false;
    } catch (_) {
      // The request may have reached the server before the connection
      // dropped, so ask the server what actually happened.
      final status = await controller.refresh();
      if (status?.attendedToday == true) {
        _message =
            '연결이 잠시 끊겼지만 오늘 출석은 정상 처리됐어요.'
            '${status!.todayPoints == null ? '' : ' (${status.todayPoints}포인트)'}';
        _messageIsError = false;
      } else {
        _message = '출석을 처리하지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.';
        _messageIsError = true;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final today = controller.status?.today;
    if (today != null) _showMonth(today);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final status = controller.status;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '매일매일 출석체크',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (status == null)
                    _StatusError(
                      loading: _loadingStatus,
                      onRetry: _reloadStatus,
                    )
                  else ...[
                    _Summary(status: status),
                    const SizedBox(height: 12),
                    ..._stampSection(status),
                    const SizedBox(height: 20),
                    _MonthHeader(
                      month: _month!,
                      onPrevious: () =>
                          _showMonth(DateTime(_month!.year, _month!.month - 1)),
                      onNext: () =>
                          _showMonth(DateTime(_month!.year, _month!.month + 1)),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<List<AttendanceDay>>(
                      future: _days,
                      builder: (context, s) => AttendanceCalendar(
                        month: _month!,
                        today: status.today,
                        days: s.data ?? const [],
                        upcoming: upcomingMilestones(status),
                        loading: s.connectionState != ConnectionState.done,
                        failed: s.hasError,
                        onRetry: () => _showMonth(_month!),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('닫기'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Stamp button (or "오늘 출석 완료!") right under the summary, so it is
  /// visible without scrolling past the calendar.
  List<Widget> _stampSection(AttendanceStatus status) => [
    if (_message != null) ...[
      _MessageCard(text: _message!, isError: _messageIsError),
      const SizedBox(height: 12),
    ],
    FilledButton.icon(
      style: FilledButton.styleFrom(
        disabledBackgroundColor: AppColors.mintTint,
        disabledForegroundColor: AppColors.mintText,
      ),
      onPressed: status.attendedToday || _busy ? null : _stamp,
      icon: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(status.attendedToday ? Icons.check_circle : Icons.approval),
      label: Text(status.attendedToday ? '오늘 출석 완료!' : '출석도장 찍기'),
    ),
  ];
}

class _Summary extends StatelessWidget {
  const _Summary({required this.status});
  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = textTheme.bodyLarge?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    );
    final upcoming = upcomingMilestones(status);
    final next = upcoming.isEmpty ? null : upcoming.first;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.tint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            status.streak > 0
                ? '🔥 ${status.streak}일 연속 출석 달성!'
                : '🔥 오늘부터 연속 출석을 시작해 보세요',
            textAlign: TextAlign.center,
            style: style?.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            '보유 포인트  🪙 ${status.balance} P',
            textAlign: TextAlign.center,
            style: style?.copyWith(color: AppColors.blueText),
          ),
          if (next != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.rewardTint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                next.stampsNeeded == 1 && !status.attendedToday
                    ? '오늘 출석하면 ⭐ ${next.streak}일 연속 달성! '
                          '(${next.points}포인트)'
                    : '앞으로 ${next.stampsNeeded}번 더 출석하면 '
                          '${next.date.month}월 ${next.date.day}일에 '
                          '⭐ ${next.streak}일 연속 달성! (${next.points}포인트)',
                textAlign: TextAlign.center,
                style: style?.copyWith(color: AppColors.rewardText),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });
  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(
        child: OutlinedButton(
          style: _monthButtonStyle,
          onPressed: onPrevious,
          child: const FittedBox(fit: BoxFit.scaleDown, child: Text('‹ 이전 달')),
        ),
      ),
      Expanded(
        flex: 2,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '${month.year}년 ${month.month}월',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
      Flexible(
        child: OutlinedButton(
          style: _monthButtonStyle,
          onPressed: onNext,
          child: const FittedBox(fit: BoxFit.scaleDown, child: Text('다음 달 ›')),
        ),
      ),
    ],
  );
}

// Compact month buttons beside the title, still a 48dp touch target.
final _monthButtonStyle = OutlinedButton.styleFrom(
  minimumSize: const Size(0, 48),
  padding: const EdgeInsets.symmetric(horizontal: 8),
  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
);

/// Month grid: stamped days, 7/14/30-day streak days and today are each
/// visually distinct. Dates are plain KST calendar dates.
class AttendanceCalendar extends StatelessWidget {
  const AttendanceCalendar({
    super.key,
    required this.month,
    required this.today,
    required this.days,
    this.upcoming = const [],
    this.loading = false,
    this.failed = false,
    this.onRetry,
  });
  final DateTime month;
  final DateTime today;
  final List<AttendanceDay> days;
  final List<UpcomingMilestone> upcoming;
  final bool loading;
  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final byDay = {for (final d in days) d.date.day: d};
    final ahead = {
      for (final u in upcoming)
        if (u.date.year == month.year && u.date.month == month.month)
          u.date.day: u,
    };
    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday % 7; // 일요일 시작
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();
    const weekdays = ['일', '월', '화', '수', '목', '금', '토'];
    final textTheme = Theme.of(context).textTheme;
    final dayStyle = textTheme.bodyLarge?.copyWith(
      fontSize: 18,
      color: AppColors.textPrimary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  weekdays[i],
                  textAlign: TextAlign.center,
                  style: dayStyle?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: i == 0 ? AppColors.danger : AppColors.textPrimary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final day = r * 7 + c - leading + 1;
                      if (day < 1 || day > daysInMonth) {
                        return const SizedBox(height: 60);
                      }
                      final date = DateTime(month.year, month.month, day);
                      return _DayCell(
                        day: day,
                        record: byDay[day],
                        isToday: date == today,
                        upcoming: ahead[day],
                        style: dayStyle,
                      );
                    },
                  ),
                ),
            ],
          ),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          )
        else if (failed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(child: Text('출석 기록을 불러오지 못했어요.', style: dayStyle)),
                TextButton(onPressed: onRetry, child: const Text('다시 시도')),
              ],
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.record,
    required this.isToday,
    required this.style,
    this.upcoming,
  });
  final int day;
  final AttendanceDay? record;
  final bool isToday;
  final TextStyle? style;

  /// Streak this day will reach if the user keeps stamping (faint star).
  final UpcomingMilestone? upcoming;

  @override
  Widget build(BuildContext context) {
    final milestone = record?.isMilestone == true;
    final attended = record != null;
    final future = !attended && upcoming != null;
    final label = attended
        ? '$day일 출석${milestone ? ', ${record!.streak}일 연속 달성' : ''}'
        : future
        ? '$day일, 계속 출석하면 ${upcoming!.streak}일 연속 달성 예정'
        : '$day일';
    return Semantics(
      label: isToday ? '오늘, $label' : label,
      excludeSemantics: true,
      child: Container(
        height: 60,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: milestone
              ? AppColors.rewardTint
              : attended
              ? AppColors.tint
              : future
              ? AppColors.rewardFaintTint
              : null,
          borderRadius: BorderRadius.circular(12),
          border: isToday
              ? Border.all(color: AppColors.primary, width: 2.5)
              : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$day',
                style: style?.copyWith(
                  fontWeight: isToday || attended
                      ? FontWeight.w800
                      : FontWeight.w500,
                ),
              ),
              if (milestone)
                const Icon(Icons.star, size: 20, color: AppColors.rewardText)
              else if (attended)
                const Icon(
                  Icons.check_circle,
                  size: 20,
                  color: AppColors.primary,
                )
              else if (future)
                const Icon(
                  Icons.star_border,
                  size: 20,
                  color: AppColors.rewardFaintText,
                )
              else
                const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.text, required this.isError});
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: isError ? AppColors.dangerTint : AppColors.rewardTint,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: isError ? AppColors.danger : AppColors.rewardText,
      ),
    ),
  );
}

class _StatusError extends StatelessWidget {
  const _StatusError({required this.loading, required this.onRetry});
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => loading
      ? const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '출석 정보를 불러오지 못했어요. 다시 시도해 주세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(fontSize: 18, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        );
}
