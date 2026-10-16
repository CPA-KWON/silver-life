import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Section title row with an optional trailing widget (e.g. "see all").
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
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

/// Circular lavender badge holding a single icon.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.size = 52,
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
        const Color(0xFFF1F2F6),
        const Color(0xFF4B5563),
      ),
      StatusPillTone.primary => (AppColors.tint, AppColors.primary),
      StatusPillTone.success => (const Color(0xFFDCFCE7), AppColors.success),
      StatusPillTone.danger => (
        const Color(0xFFFEE2E2),
        const Color(0xFFB91C1C),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
