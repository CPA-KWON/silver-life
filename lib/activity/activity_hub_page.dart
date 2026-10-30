import '../core/points.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../ui/design_widgets.dart';
import '../attendance/attendance_controller.dart';
import '../attendance/attendance_dialog.dart';
import '../pet/pet_design.dart';
import '../pet/pet_preview_controller.dart';
import '../pet/pet_repository.dart';
import '../pet/pet_preview_pages.dart';
import 'activity_hub_widgets.dart';
import 'activity_repository.dart';
import 'activity_forms.dart';
import 'activity_detail_page.dart';
import 'activity_design.dart';
import 'saved_programs_page.dart';
import 'activity_program_card.dart';
import 'activity_place_match.dart';
import 'activity_welfare_catalog.dart';
import 'activity_welfare_detail.dart';

part 'activity_section_views.dart';

enum ActivitySection {
  find,
  missions,
  mine,
  experience,
  programs,
  myExperiences,
  recruitment,
  support,
}

String activitySectionTitle(ActivitySection section) => switch (section) {
  ActivitySection.find => '맞춤 활동 찾기',
  ActivitySection.missions => '프로그램별 주간 미션',
  ActivitySection.mine => '나의 활동',
  ActivitySection.experience => '경험 나눔',
  ActivitySection.programs => '전체 프로그램',
  ActivitySection.myExperiences => '내 경험 관리',
  ActivitySection.recruitment => '기관 모집 탐색',
  ActivitySection.support => '경험 나눔 지원 현황',
};

/// Four focused destinations, backed by the existing wallet and pet missions.
class ActivityHubPage extends StatefulWidget {
  const ActivityHubPage({
    super.key,
    this.repository,
    this.petController,
    this.onOpenPet,
    this.onAttendanceChanged,
  });
  final ActivityRepository? repository;
  final PetPreviewController? petController;
  final VoidCallback? onOpenPet;
  final Future<void> Function()? onAttendanceChanged;
  @override
  State<ActivityHubPage> createState() => _ActivityHubState();
}

class _ActivityHubState extends State<ActivityHubPage> {
  final search = TextEditingController();
  late final pet =
      widget.petController ?? PetPreviewController(repository: PetRepository());
  @override
  void initState() {
    super.initState();
    if (widget.petController == null) unawaited(pet.load());
  }

  @override
  void dispose() {
    search.dispose();
    if (widget.petController == null) pet.dispose();
    super.dispose();
  }

  Future<void> open(Widget page) async {
    FocusScope.of(context).unfocus();
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) await pet.load();
  }

  void section(ActivitySection value, {String query = '', String? category}) =>
      open(
        ActivitySectionPage(
          section: value,
          repository: widget.repository,
          initialQuery: query,
          initialCategory: category,
        ),
      );
  void openPet() {
    if (widget.onOpenPet != null) {
      widget.onOpenPet!();
    } else {
      open(
        !pet.ready
            ? PetConnectionPage(pet: pet)
            : pet.adopted
            ? PetHomePage(pet: pet)
            : PetAdoptionPage(pet: pet),
      );
    }
  }

  Future<void> calendar() async {
    final attendance = AttendanceScope.maybeOf(context);
    if (attendance == null) return;
    await showAttendanceDialog(context, attendance);
    if (!mounted) return;
    if (widget.onAttendanceChanged != null) {
      await widget.onAttendanceChanged!();
    } else {
      await pet.load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: PetColors.background,
    body: RefreshIndicator(
      onRefresh: pet.load,
      child: ListenableBuilder(
        listenable: pet,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              children: [
                Text('활동', style: petText(32, weight: FontWeight.w800)),
                ActivityWalletPill(
                  balance: AttendanceScope.maybeOf(context)?.status?.balance,
                  onTap: calendar,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '오늘 할 수 있는 동네 활동을 찾아보세요',
              style: petText(
                17,
                color: PetColors.secondary,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            ActivityDiscoveryCard(
              controller: search,
              onFind: () => section(ActivitySection.find),
              onSearch: (value) {
                final query = value.trim();
                section(
                  query.isEmpty
                      ? ActivitySection.find
                      : ActivitySection.programs,
                  query: query,
                );
              },
              onCategory: (label) => section(
                ActivitySection.programs,
                category: activityQuickCategories[label],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ActivityButton(
                '전체 프로그램 보기',
                light: true,
                icon: Icons.apps_outlined,
                onTap: () => section(ActivitySection.programs),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () =>
                    open(SavedProgramsPage(repository: widget.repository)),
                icon: const Icon(Icons.favorite_border_rounded),
                label: const Text('관심 프로그램'),
              ),
            ),
            const SizedBox(height: 14),
            ActivityWeeklyCard(
              missions: pet.missions,
              loaded: pet.ready,
              adopted: pet.adopted,
              hasError: pet.error != null,
              onTap: () => open(
                PetTodayPage(
                  pet: pet,
                  missionsOnly: true,
                  onOpenPet: openPet,
                  onOpenProgramMissions: () =>
                      section(ActivitySection.missions),
                ),
              ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (c, b) {
                final single =
                    b.maxWidth < 330 ||
                    MediaQuery.textScalerOf(c).scale(1) > 1.4;
                final mine = ActivityPurposeTile(
                  title: '나의 활동',
                  description: '신청 상태·참여 이력\n혜택',
                  icon: Icons.event_available_outlined,
                  color: const Color(0xFF298F5C),
                  tint: const Color(0xFFE5F6EE),
                  onTap: () => section(ActivitySection.mine),
                );
                final experience = ActivityPurposeTile(
                  title: '경험 나눔',
                  description: '내 경험 관리와\n기관 모집 지원',
                  icon: Icons.favorite_rounded,
                  color: const Color(0xFFE7528E),
                  tint: const Color(0xFFFCECF4),
                  onTap: () => section(ActivitySection.experience),
                );
                return single
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          mine,
                          const SizedBox(height: 12),
                          experience,
                        ],
                      )
                    : IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: mine),
                            const SizedBox(width: 12),
                            Expanded(child: experience),
                          ],
                        ),
                      );
              },
            ),
            const SizedBox(height: 14),
            Material(
              color: const Color(0xFFEDE8FF),
              borderRadius: BorderRadius.circular(28),
              child: InkWell(
                onTap: openPet,
                borderRadius: BorderRadius.circular(28),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        height: 62,
                        child: PetPhoto(
                          pet: pet,
                          mood: 'greeting',
                          outfit: const {},
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '활동하면 콩이도 자라요',
                              style: petText(19, weight: FontWeight.w800),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '참여 확인되면 포인트·성장 경험치 지급',
                              style: petText(15, color: PetColors.purple),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: PetColors.purple,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ActivityMenuLink extends StatelessWidget {
  const ActivityMenuLink({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.color = AppColors.surface,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SectionCard(
      color: color,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon: icon, size: 48),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.primary),
            ],
          ),
        ),
      ),
    ),
  );
}

class ActivitySectionPage extends StatefulWidget {
  const ActivitySectionPage({
    super.key,
    required this.section,
    this.repository,
    this.place,
    this.initialQuery = '',
    this.initialCategory,
  });
  final ActivitySection section;
  final String initialQuery;
  final String? initialCategory;
  final ({String name, double lat, double lng})? place;
  final ActivityRepository? repository;
  @override
  State<ActivitySectionPage> createState() => _ActivitySectionPageState();
}
