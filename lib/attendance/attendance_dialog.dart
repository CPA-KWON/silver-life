import '../core/points.dart';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'attendance_controller.dart';
import 'attendance_repository.dart';
import 'attendance_ads.dart';

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
  const AttendanceDialog({super.key, required this.controller, this.ads});
  final AttendanceAds? ads;
  final AttendanceController controller;

  @override
  State<AttendanceDialog> createState() => _AttendanceDialogState();
}

class _AttendanceDialogState extends State<AttendanceDialog> {
  AttendanceController get controller => widget.controller;
  DateTime? _month;
  Future<List<AttendanceDay>>? _days;
  bool _busy = false;
  bool _adBusy = false;
  AttendanceAdOffer? _offer;
  AttendanceAdResult? _adResult;
  int _testViews = 0;
  String? _adDay;
  late final ads = widget.ads ?? AttendanceAds();
  Future<void> _loadAdOffer() async {
    final status = controller.status;
    if (status == null) return;
    try {
      final offer = await ads.offer(
        streak: status.streak,
        attended: status.attendedToday,
      );
      if (mounted) {
        setState(() {
          if (_adDay != '${status.today}') {
            _testViews = 0;
            _adDay = '${status.today}';
          }
          _offer = offer;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _offer = null);
    }
  }

  Future<void> _watchAd() async {
    if (_adBusy || _offer == null) return;
    setState(() {
      _adBusy = true;
      _adResult = null;
    });
    try {
      final result = await ads.watch();
      if (!mounted) return;
      setState(() {
        _adResult = result;
        if (ads.testing && result == AttendanceAdResult.completed) _testViews++;
      });
      if (!ads.testing) await controller.refresh();
      await _loadAdOffer();
    } catch (_) {
      if (mounted) setState(() => _adResult = AttendanceAdResult.unavailable);
    } finally {
      if (mounted) setState(() => _adBusy = false);
    }
  }

  bool _loadingStatus = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _loadAdOffer();
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
    if (status != null) {
      _showMonth(_month ?? status.today);
      await _loadAdOffer();
    }
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
            '${status!.todayPoints == null ? '' : ' (${pointAmount(status.todayPoints)}포인트)'}';
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
    await _loadAdOffer();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      canPop: !_adBusy,
      child: Dialog(
        backgroundColor: const Color(0xFFF4F9FC),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final status = controller.status;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '출석체크',
                                  style: textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '닫기',
                                onPressed: _adBusy
                                    ? null
                                    : () => Navigator.pop(context),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (status == null)
                            _StatusError(
                              loading: _loadingStatus,
                              onRetry: _reloadStatus,
                            )
                          else ...[
                            _Summary(status: status),
                            const SizedBox(height: 16),
                            _MonthHeader(
                              month: _month!,
                              onPrevious: () => _showMonth(
                                DateTime(_month!.year, _month!.month - 1),
                              ),
                              onNext: () => _showMonth(
                                DateTime(_month!.year, _month!.month + 1),
                              ),
                            ),
                            const SizedBox(height: 8),
                            FutureBuilder<List<AttendanceDay>>(
                              future: _days,
                              builder: (context, s) => AttendanceCalendar(
                                month: _month!,
                                today: status.today,
                                days: s.data ?? const [],
                                upcoming: upcomingMilestones(status),
                                onTapToday: status.attendedToday || _busy
                                    ? null
                                    : _stamp,
                                loading:
                                    s.connectionState != ConnectionState.done,
                                failed: s.hasError,
                                onRetry: () => _showMonth(_month!),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ..._stampSection(status),
                            const SizedBox(height: 10),
                            if (!ads.visible)
                              const SizedBox.shrink()
                            else if (status.attendedToday)
                              _adCard()
                            else
                              const Padding(
                                padding: EdgeInsets.all(10),
                                child: Text(
                                  'ⓘ 출석하면 광고 보너스가 열려요',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _adBusy
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('닫기'),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _adCard() {
    final remaining =
        ((_offer?.remaining ?? 2) - (ads.testing ? _testViews : 0)).clamp(0, 2);
    final done = remaining == 0 && _offer?.enabled == true;
    final title = _adBusy
        ? '광고 준비 중'
        : done
        ? '오늘은 다 받았어요'
        : switch (_adResult) {
            AttendanceAdResult.completed =>
              ads.testing
                  ? '테스트 시청 완료'
                  : '+${pointAmount(_offer?.points ?? 20)}P 받았어요',
            AttendanceAdResult.cancelled => '끝까지 봐야 받아요',
            AttendanceAdResult.unavailable => '지금은 광고가 없어요',
            AttendanceAdResult.pending => '보상을 확인하고 있어요',
            _ => '광고 보고 +${pointAmount(_offer?.points ?? 20)}P',
          };
    final subtitle = _adBusy
        ? '잠시만 기다려 주세요'
        : done
        ? '내일 다시 만나요'
        : _adResult == AttendanceAdResult.cancelled
        ? '포인트는 그대로예요'
        : _adResult == AttendanceAdResult.unavailable
        ? '잠시 뒤 다시 시도해 주세요'
        : '원할 때만 · 오늘 $remaining번';
    return Container(
      key: const ValueKey('attendance-ad-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFFE2F2FB), Color(0xFFE8EEFC)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (_adBusy)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                TextButton(
                  onPressed: done
                      ? null
                      : _offer == null
                      ? _loadAdOffer
                      : _offer!.enabled
                      ? _watchAd
                      : null,
                  child: Text(
                    done
                        ? '내일'
                        : _offer == null
                        ? '다시'
                        : '▶ 보기',
                  ),
                ),
            ],
          ),
          if (ads.testing)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '테스트 광고 · 실제 포인트는 지급되지 않아요',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  /// Stamp button (or "오늘 출석 완료!") with its result message, under the
  /// calendar.
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
      label: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        children: [
          Text(status.attendedToday ? '오늘 출석 완료!' : '출석하기'),
          Text(
            '+${pointAmount(status.attendedToday ? status.todayPoints ?? 1 : attendanceMilestonePoints[status.streak + 1] ?? attendanceBasePoints)}P',
          ),
        ],
      ),
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
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    );
    final upcoming = upcomingMilestones(status);
    final next = upcoming.isEmpty ? null : upcoming.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD2EDF8), Color(0xFFE1E6FE)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Line 1: streak and points side by side (wraps on narrow phones).
          Row(
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status.streak > 0 ? '${status.streak}일째 연속' : '오늘 출석해요',
                  style: style,
                ),
              ),
              Text('${pointAmount(status.balance)} P', style: style),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 1; i <= 7; i++)
                Expanded(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: status.streak >= i
                            ? AppColors.primary
                            : Colors.white,
                        child: Icon(
                          i == 7 ? Icons.star_rounded : Icons.pets_rounded,
                          size: 15,
                          color: status.streak >= i
                              ? Colors.white
                              : i == 7
                              ? Colors.orange
                              : const Color(0xFFD4E1EA),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Line 2: next star day.
          if (next != null) ...[
            const SizedBox(height: 6),
            Text(
              next.stampsNeeded == 1 && !status.attendedToday
                  ? '오늘 ${next.streak}일 연속 달성 · ${pointAmount(next.points)}P'
                  : '${next.streak}일 연속까지 ${next.stampsNeeded}일 · ${pointAmount(next.points)}P',
              textAlign: TextAlign.center,
              style: style?.copyWith(color: AppColors.rewardText),
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
    this.onTapToday,
    this.loading = false,
    this.failed = false,
    this.onRetry,
  });
  final DateTime month;
  final DateTime today;
  final List<AttendanceDay> days;
  final List<UpcomingMilestone> upcoming;

  /// Set while today is not stamped: tapping today's cell stamps it.
  final VoidCallback? onTapToday;
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
                        onTap: date == today ? onTapToday : null,
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
    this.onTap,
  });
  final int day;
  final AttendanceDay? record;
  final bool isToday;
  final TextStyle? style;

  /// Streak this day will reach if the user keeps stamping (faint star).
  final UpcomingMilestone? upcoming;
  final VoidCallback? onTap;

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
    final cell = Container(
      height: 44,
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
              const Icon(Icons.pets_rounded, size: 20, color: AppColors.primary)
            else if (future)
              const Icon(
                Icons.star_border,
                size: 20,
                color: AppColors.rewardFaintText,
              )
            else if (onTap != null)
              const Icon(Icons.approval, size: 20, color: AppColors.primary)
            else
              const SizedBox(height: 20),
          ],
        ),
      ),
    );
    return Semantics(
      label: isToday
          ? '오늘, $label${onTap != null ? ', 눌러서 출석도장 찍기' : ''}'
          : label,
      button: onTap != null,
      excludeSemantics: true,
      child: onTap == null
          ? cell
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: cell,
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
