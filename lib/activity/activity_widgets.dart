import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../ui/design_widgets.dart';
import 'activity_repository.dart';
import 'activity_program_card.dart';
import 'activity_design.dart';

Future<bool> activityConfirm(
  BuildContext context,
  String title,
  String message,
) => activityDialog(context, title: title, message: message);
void activityMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

class ActivityInfo extends StatelessWidget {
  const ActivityInfo(
    this.message, {
    super.key,
    this.onRetry,
    this.color = AppColors.surface,
  });
  final String message;
  final VoidCallback? onRetry;
  final Color color;
  @override
  Widget build(BuildContext context) => SectionCard(
    color: color,
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
    this.color = AppColors.surface,
  });
  final ActivityData program;
  final VoidCallback onTap;
  final String? label;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      ActivityListingCard(program: program, onTap: onTap, label: label);
}
