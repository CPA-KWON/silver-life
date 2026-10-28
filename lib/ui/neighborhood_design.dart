import 'package:flutter/material.dart';

import '../activity/activity_design.dart';
import '../attendance/point_badge.dart';
import '../pet/pet_design.dart';
export '../activity/activity_design.dart';
export '../pet/pet_design.dart';

const neighborhoodMint = Color(0xFFD7F1E5),
    neighborhoodLavender = Color(0xFFE6E1FF),
    neighborhoodAmber = Color(0xFFFFE8BD);

class NeighborhoodScreen extends StatelessWidget {
  const NeighborhoodScreen({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.tint = neighborhoodMint,
    this.back = true,
    this.onBack,
    this.actions = const [],
    this.bottom,
    this.floating,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final Color tint;
  final bool back;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Widget? bottom, floating;
  @override
  Widget build(BuildContext c) => Scaffold(
    backgroundColor: PetColors.background,
    floatingActionButton: floating,
    body: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, .62],
          colors: [tint, PetColors.background],
        ),
      ),
      child: SafeArea(
        top: !Navigator.of(c).canPop() ? false : true,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (back) ...[
                        Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: '뒤로',
                            onPressed: onBack ?? () => Navigator.maybePop(c),
                            icon: const Icon(
                              Icons.chevron_left_rounded,
                              size: 30,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          style: petText(
                            back ? 25 : 30,
                            weight: FontWeight.w800,
                          ),
                        ),
                      ),
                      ...actions,
                      if (actions.isEmpty) const PointBadge(),
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle!,
                      style: petText(18, color: PetColors.secondary),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(child: child),
            if (bottom != null)
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: bottom!,
              ),
          ],
        ),
      ),
    ),
  );
}

class NeighborhoodHeading extends StatelessWidget {
  const NeighborhoodHeading(
    this.label, {
    super.key,
    this.count,
    this.color = PetColors.green,
  });
  final String label;
  final String? count;
  final Color color;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 12),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(label, style: petText(22))),
        if (count != null)
          Text(count!, style: petText(16, color: PetColors.secondary)),
      ],
    ),
  );
}

class NeighborhoodHero extends StatelessWidget {
  const NeighborhoodHero({
    super.key,
    required this.title,
    this.subtitle,
    this.tags = const [],
    this.color = PetColors.green,
  });
  final String title;
  final String? subtitle;
  final List<Widget> tags;
  final Color color;
  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: LinearGradient(
        colors: [color, Color.lerp(color, Colors.black, .25)!],
      ),
      boxShadow: PetColors.softShadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tags.isNotEmpty) ...[
          Wrap(spacing: 6, runSpacing: 6, children: tags),
          const SizedBox(height: 14),
        ],
        Text(
          title,
          style: petText(25, color: Colors.white, weight: FontWeight.w800),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 14),
          Text(subtitle!, style: petText(16, color: Colors.white)),
        ],
      ],
    ),
  );
}

class NeighborhoodLoading extends StatelessWidget {
  const NeighborhoodLoading({super.key});
  @override
  Widget build(BuildContext c) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      for (var i = 0; i < 3; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: ActivityCard(
            child: Column(
              children: [
                Container(height: 18, color: const Color(0xFFEDF2F6)),
                const SizedBox(height: 12),
                Container(height: 45, color: const Color(0xFFF3F5F7)),
              ],
            ),
          ),
        ),
      const Center(child: CircularProgressIndicator()),
    ],
  );
}

class NeighborAvatar extends StatelessWidget {
  const NeighborAvatar(
    this.name, {
    super.key,
    this.radius = 22,
    this.color = const Color(0xFF40A5D6),
  });
  final String name;
  final double radius;
  final Color color;
  @override
  Widget build(BuildContext c) => CircleAvatar(
    radius: radius,
    backgroundColor: color,
    child: Text(
      name.isEmpty ? '이' : name.characters.first,
      style: petText(radius * .8, color: Colors.white),
    ),
  );
}
