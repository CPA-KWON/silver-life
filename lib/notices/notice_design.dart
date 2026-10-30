import 'package:flutter/material.dart';

import '../pet/pet_design.dart';
import 'notice_repository.dart';

/// '내 복지관' mockup (2026-10-30) tokens: blue institution theme, grey
/// homepage-collected tag, green tag for notices the institution wrote itself.
abstract final class NoticeColors {
  static const ink = Color(0xFF13202E),
      blue = Color(0xFF0B6FA8),
      label = Color(0xFF0A6399),
      text = Color(0xFF33475B),
      muted = Color(0xFF6A7B8B),
      line = Color(0xFFEEF2F6),
      soft = Color(0xFFF4F8FB),
      chip = Color(0xFFEEF4FA),
      sky = Color(0xFFEAF3FB),
      tint = Color(0xFFDCEBF7),
      red = Color(0xFFE5484D),
      success = Color(0xFF1E8A57);
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0, .55, 1],
    colors: [Color(0xFF1C8FD0), Color(0xFF0B6FA8), Color(0xFF08598A)],
  );
  static const shadow = [
    BoxShadow(color: Color(0x1A0F2D50), blurRadius: 24, offset: Offset(0, 10)),
  ];
}

String noticeLongDate(dynamic value) {
  final d = DateTime.tryParse('$value')?.toLocal();
  return d == null ? '' : '${d.year}년 ${d.month}월 ${d.day}일';
}

String noticeShortDate(dynamic value) {
  final d = DateTime.tryParse('$value')?.toLocal();
  return d == null
      ? ''
      : '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
}

String noticeDotDate(dynamic value) {
  final d = DateTime.tryParse('$value')?.toLocal();
  return d == null
      ? ''
      : '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
}

class InstitutionLogo extends StatelessWidget {
  const InstitutionLogo({super.key, this.size = 54, this.soft = false});
  final double size;
  final bool soft;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size / 3),
      gradient: soft
          ? const LinearGradient(colors: [Color(0xFFEAF4FC), Color(0xFFD6E9F8)])
          : NoticeColors.gradient,
    ),
    child: Icon(
      Icons.apartment_rounded,
      size: size * .52,
      color: soft ? NoticeColors.blue : Colors.white,
    ),
  );
}

class NoticeSourceTag extends StatelessWidget {
  const NoticeSourceTag(this.notice, {super.key});
  final NoticeData notice;
  @override
  Widget build(BuildContext context) {
    final official = notice['is_public_source'] != true;
    return _Tag(
      official ? '기관 직접 등록' : '홈페이지 원문',
      icon: official ? Icons.check_rounded : Icons.description_outlined,
      color: official ? const Color(0xFFE2F6EC) : const Color(0xFFEEF1F4),
      ink: official ? const Color(0xFF14633F) : const Color(0xFF4A5B6B),
    );
  }
}

class NoticeNewBadge extends StatelessWidget {
  const NoticeNewBadge({super.key});
  @override
  Widget build(BuildContext context) =>
      const _Tag('새 소식', color: Color(0xFFFDECEC), ink: Color(0xFFC0392B));
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {required this.color, required this.ink, this.icon});
  final String label;
  final Color color, ink;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: ink),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            style: petText(13, color: ink, weight: FontWeight.w900),
          ),
        ),
      ],
    ),
  );
}

/// One notice in a list: source tag (+ 새 소식), title, posting date.
class NoticeListCard extends StatelessWidget {
  const NoticeListCard(
    this.notice, {
    super.key,
    required this.onTap,
    this.showInstitution = false,
    this.showNew = true,
  });
  final NoticeData notice;
  final VoidCallback onTap;
  final bool showInstitution, showNew;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: NoticeColors.shadow,
      ),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: notice['important'] == true
              ? const BorderSide(color: PetColors.orange, width: 2)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    NoticeSourceTag(notice),
                    if (showNew && isNewNotice(notice)) const NoticeNewBadge(),
                    if (notice['important'] == true)
                      const _Tag(
                        '중요',
                        color: Color(0xFFFFE9E7),
                        ink: Colors.redAccent,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${notice['title']}',
                  style: petText(
                    19,
                    color: NoticeColors.ink,
                    weight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                        color: NoticeColors.muted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [
                          '게시 ${noticeDotDate(notice['published_at'] ?? notice['created_at'])}',
                          if (showInstitution &&
                              '${notice['org_name'] ?? ''}'.isNotEmpty)
                            '${notice['org_name']}',
                        ].join(' · '),
                        style: petText(15, color: NoticeColors.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pill button from the mockup: blue gradient, light blue secondary, or grey
/// when disabled. Optional [badge] is shown inside (e.g. '새 소식 2').
class NoticeButton extends StatelessWidget {
  const NoticeButton(
    this.label, {
    super.key,
    required this.onTap,
    this.secondary = false,
    this.icon,
    this.badge,
    this.busy = false,
    this.color,
  });
  final String label;
  final VoidCallback? onTap;
  final bool secondary, busy;
  final IconData? icon;
  final String? badge;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null && !busy;
    final ink = secondary ? NoticeColors.label : Colors.white;
    return Semantics(
      container: true,
      button: true,
      enabled: !disabled,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: disabled
              ? const Color(0xFFDCE5ED)
              : secondary
              ? NoticeColors.sky
              : color,
          gradient: disabled || secondary || color != null
              ? null
              : NoticeColors.gradient,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: busy ? null : onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 58),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (busy)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      )
                    else if (icon != null)
                      Icon(
                        icon,
                        size: 22,
                        color: disabled ? NoticeColors.muted : ink,
                      ),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: petText(
                        18,
                        color: disabled ? NoticeColors.muted : ink,
                        weight: FontWeight.w900,
                      ),
                    ),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .25),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          badge!,
                          style: petText(
                            15,
                            color: ink,
                            weight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small grey '변경' pill next to the institution name.
class NoticeChipButton extends StatelessWidget {
  const NoticeChipButton(this.label, {super.key, required this.onTap});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    child: Material(
      color: NoticeColors.chip,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: petText(
                  15,
                  color: NoticeColors.text,
                  weight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Empty / error / guidance block: tinted icon, title, message, buttons.
class NoticeStateCard extends StatelessWidget {
  const NoticeStateCard({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.onAction,
    this.actionIcon,
    this.secondary,
    this.onSecondary,
    this.error = false,
  });
  final IconData icon;
  final String title;
  final String? message, action, secondary;
  final VoidCallback? onAction, onSecondary;
  final IconData? actionIcon;
  final bool error;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      boxShadow: NoticeColors.shadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: error ? const Color(0xFFFDECEC) : NoticeColors.sky,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              icon,
              size: 34,
              color: error ? NoticeColors.red : NoticeColors.blue,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: petText(19, color: NoticeColors.ink, weight: FontWeight.w800),
        ),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: petText(
              16,
              color: const Color(0xFF5A6B7B),
              weight: FontWeight.w600,
            ),
          ),
        ],
        if (action != null) ...[
          const SizedBox(height: 16),
          NoticeButton(action!, icon: actionIcon, onTap: onAction),
        ],
        if (secondary != null) ...[
          const SizedBox(height: 8),
          NoticeButton(secondary!, secondary: true, onTap: onSecondary),
        ],
      ],
    ),
  );
}

class NoticeHint extends StatelessWidget {
  const NoticeHint(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: NoticeColors.muted,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: petText(15, color: NoticeColors.muted)),
        ),
      ],
    ),
  );
}

/// Grey placeholder rows while a list loads.
class NoticeSkeleton extends StatelessWidget {
  const NoticeSkeleton({super.key, this.count = 4, this.label = '불러오고 있어요'});
  final int count;
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Column(
      children: [
        for (var i = 0; i < count; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (w, h) in [(.55 + (i % 3) * .12, 22.0), (.4, 16.0)])
                  FractionallySizedBox(
                    widthFactor: w,
                    child: Container(
                      height: h,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Green confirmation toast that survives the route pop it follows.
void showNoticeToast(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: NoticeColors.success,
        shape: const StadiumBorder(),
        margin: const EdgeInsets.fromLTRB(32, 0, 32, 110),
        duration: const Duration(seconds: 3),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                style: petText(
                  16,
                  color: Colors.white,
                  weight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}
