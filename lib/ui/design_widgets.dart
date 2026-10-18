import 'package:flutter/material.dart';

import '../app_theme.dart';

/// The mockup's ring uses actual mission counts; an empty week is not 0/3.
class WeeklyActivitySummary extends StatelessWidget {
  const WeeklyActivitySummary({
    super.key,
    required this.completed,
    required this.total,
    required this.upcoming,
    required this.onOpen,
  });
  final int completed, total, upcoming;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          '이번 주 활동 현황',
          style: text.titleLarge?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 12),
        SizedBox.square(
          dimension: MediaQuery.textScalerOf(context)
              .scale(180)
              .clamp(180, 240),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: Alignment(-0.4, -0.5),
                    colors: [AppColors.primary, AppColors.heroCircle],
                  ),
                ),
              ),
              ExcludeSemantics(
                child: CircularProgressIndicator(
                  value: total == 0 ? 0 : (completed / total).clamp(0, 1),
                  strokeWidth: 3,
                  backgroundColor: AppColors.heroTrack,
                  color: AppColors.heroProgress,
                  strokeCap: StrokeCap.round,
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      total == 0 ? '시작 전' : '$completed',
                      style: text.displayLarge?.copyWith(
                        fontSize: total == 0 ? 28 : 56,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    if (total != 0)
                      Text(
                        '개 완료',
                        style: text.bodyLarge?.copyWith(color: Colors.white),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '예정 활동 $upcoming개 · ${total == 0 ? '미션 미생성' : '미션 $completed/$total개 완료'}',
          textAlign: TextAlign.center,
          style: text.bodyLarge?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: AppColors.heroCircle,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            shape: const StadiumBorder(),
          ),
          onPressed: onOpen,
          child: const Text('나의 활동 보기'),
        ),
      ],
    );
  }
}

/// Section title row with an optional trailing widget (e.g. "see all").
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Circular blue badge holding a single icon.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.size = 40,
    this.color,
    this.background,
  });

  final IconData icon;
  final double size;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? AppColors.tint,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: size * 0.5, color: color ?? AppColors.primary),
    );
  }
}

/// Color tone of a [StatusPill].
enum StatusPillTone { neutral, primary, success, danger }

/// Small rounded status label (e.g. "recruiting", "closed").
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = StatusPillTone.neutral,
  });

  final String label;
  final StatusPillTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      StatusPillTone.neutral => (
        const Color(0xFFF1F2F4),
        AppColors.scheduleText,
      ),
      StatusPillTone.primary => (AppColors.tint, AppColors.primary),
      StatusPillTone.success => (AppColors.mintTint, AppColors.mintText),
      StatusPillTone.danger => (
        const Color(0xFFFEE2E2),
        const Color(0xFFB91C1C),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}

/// In-page large title (22/600) for tab screens that have no AppBar.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

/// White rounded card with an optional header; no border or shadow.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.header,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    this.color = AppColors.surface,
  });

  final Widget? header;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(26),
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [?header, child],
        ),
      ),
    );
  }
}

/// Size variant of a [DateBlock].
enum DateBlockSize { large, compact }

/// Month / day / weekday tile used for schedule items.
class DateBlock extends StatelessWidget {
  const DateBlock({
    super.key,
    required this.date,
    this.size = DateBlockSize.large,
    this.muted = false,
  });

  final DateTime date;
  final DateBlockSize size;
  final bool muted;

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final large = size == DateBlockSize.large;
    final theme = Theme.of(context).textTheme;
    final bg = large
        ? AppColors.surface
        : (muted ? AppColors.neutralTint : AppColors.tint);
    final monthColor = muted ? AppColors.scheduleText : AppColors.primary;
    final dayColor = muted ? AppColors.scheduleText : AppColors.textPrimary;
    final dayStyle = large
        ? theme.headlineSmall
        : theme.headlineSmall?.copyWith(fontSize: 20);
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: large ? 60 : 52),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${date.month}월',
                style: theme.labelSmall?.copyWith(color: monthColor),
              ),
              Text(
                '${date.day}',
                style: dayStyle?.copyWith(
                  color: dayColor,
                  fontWeight: muted ? FontWeight.w600 : FontWeight.w700,
                  height: 1.15,
                ),
              ),
              Text(
                _weekdays[date.weekday - 1],
                style: theme.bodySmall?.copyWith(color: AppColors.scheduleText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tone of a [TagBadge].
enum TagTone { lavender, blue, mint, neutral }

/// Small rounded category tag; screens map categories to tones.
class TagBadge extends StatelessWidget {
  const TagBadge({
    super.key,
    required this.label,
    this.tone = TagTone.lavender,
  });

  final String label;
  final TagTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      TagTone.lavender => (AppColors.tint, AppColors.primary),
      TagTone.blue => (AppColors.blueTint, AppColors.blueText),
      TagTone.mint => (AppColors.mintTint, AppColors.mintText),
      TagTone.neutral => (AppColors.neutralTint, AppColors.scheduleText),
    };
    return DecoratedBox(
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
        ),
      ),
    );
  }
}
