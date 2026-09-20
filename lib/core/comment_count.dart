import 'package:flutter/material.dart';

/// Reads the aggregate count out of a PostgREST embedded-count select
/// (`comments(count)`), which comes back as `[{'count': N}]`.
int commentCountOf(Map<String, dynamic> post) {
  final rows = post['comments'] as List?;
  if (rows == null || rows.isEmpty) return 0;
  return (rows.first as Map)['count'] as int? ?? 0;
}

class CommentCountBadge extends StatelessWidget {
  const CommentCountBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.mode_comment_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 4),
        Text('$count', style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
