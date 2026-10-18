import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../ui/design_widgets.dart';
import 'activity_repository.dart';

Future<bool> activityConfirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('확인'),
          ),
        ],
      ),
    ) ??
    false;
void activityMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

class ActivityInfo extends StatelessWidget {
  const ActivityInfo(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => SectionCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
      ],
    ),
  );
}

class ActivityProgramCard extends StatelessWidget {
  const ActivityProgramCard({
    super.key,
    required this.program,
    required this.onTap,
    this.label,
  });
  final ActivityData program;
  final VoidCallback onTap;
  final String? label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SectionCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (label != null)
                Text(
                  label!,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: AppColors.primary),
                ),
              if (program['sponsored'] == true)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    '기관 후원 · 우선 노출',
                    style: TextStyle(color: AppColors.primary),
                  ),
                ),
              Text(
                program['title'] ?? '',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '${program['org_name'] ?? ''} · ${program['category'] ?? ''}',
              ),
              Text(
                '${program['place_name'] ?? ''} · ${activityDate(program['starts_at'])}',
              ),
              Text(
                '${activityMoney(program['fee'])} · ${program['enrolled'] ?? 0}/${program['capacity']}명${program['distance_km'] == null ? '' : ' · ${(program['distance_km'] as num).toStringAsFixed(1)}km'}',
              ),
              const Align(
                alignment: Alignment.centerRight,
                child: Icon(Icons.chevron_right, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
