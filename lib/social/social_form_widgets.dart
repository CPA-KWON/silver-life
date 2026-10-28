import 'package:flutter/material.dart';

import '../ui/neighborhood_design.dart';

class SocialFormCard extends StatelessWidget {
  const SocialFormCard(
    this.label, {
    super.key,
    required this.child,
    this.required = false,
  });
  final String label;
  final Widget child;
  final bool required;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: ActivityCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$label${required ? ' · 필수' : ''}', style: petText(17)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

Future<DateTime?> pickSocialDate(BuildContext context, DateTime? initial) =>
    showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) {
        final now = DateUtils.dateOnly(DateTime.now());
        var selected = initial != null && initial.isAfter(now) ? initial : now;
        return StatefulBuilder(
          builder: (c, set) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('날짜 고르기', style: petText(25)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final v in [
                        ('오늘', 0),
                        ('내일', 1),
                        ('이번 주말', (DateTime.saturday - now.weekday + 7) % 7),
                        ('다음 주', 7),
                      ])
                        ChoiceChip(
                          label: Text(v.$1),
                          selected: DateUtils.isSameDay(
                            selected,
                            now.add(Duration(days: v.$2)),
                          ),
                          onSelected: (_) => set(
                            () => selected = now.add(Duration(days: v.$2)),
                          ),
                        ),
                    ],
                  ),
                  CalendarDatePicker(
                    initialDate: selected,
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365)),
                    onDateChanged: (d) => set(() => selected = d),
                  ),
                  ActivityButton(
                    '이 날짜로 정하기',
                    onTap: () => Navigator.pop(c, selected),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
Future<TimeOfDay?> pickSocialTime(BuildContext context, TimeOfDay? initial) =>
    showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) {
        var hour = initial?.hour ?? 9, minute = initial?.minute ?? 0;
        return StatefulBuilder(
          builder: (c, set) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('시간 고르기', style: petText(25)),
                  const SizedBox(height: 16),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('오전')),
                      ButtonSegment(value: true, label: Text('오후')),
                    ],
                    selected: {hour >= 12},
                    onSelectionChanged: (v) =>
                        set(() => hour = hour % 12 + (v.first ? 12 : 0)),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var h = 1; h <= 12; h++)
                        ChoiceChip(
                          label: Text('$h시'),
                          selected: (hour % 12 == 0 ? 12 : hour % 12) == h,
                          onSelected: (_) =>
                              set(() => hour = h % 12 + (hour >= 12 ? 12 : 0)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in {
                        0,
                        10,
                        20,
                        30,
                        40,
                        50,
                        minute,
                      }.toList()..sort())
                        ChoiceChip(
                          label: Text('$m분'),
                          selected: minute == m,
                          onSelected: (_) => set(() => minute = m),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ActivityButton(
                    '이 시간으로 정하기',
                    onTap: () =>
                        Navigator.pop(c, TimeOfDay(hour: hour, minute: minute)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
