import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silver_life/activity/activity_detail_page.dart';
import 'package:silver_life/activity/activity_forms.dart';
import 'package:silver_life/activity/activity_hub_page.dart';
import 'package:silver_life/activity/activity_support_page.dart';
import 'package:silver_life/activity/activity_weekly_page.dart';
import 'package:silver_life/pet/pet_preview_controller.dart';

import 'support/fake_activity_repository.dart';
import 'support/widget_actions.dart';

class PendingApplyRepository extends FakeActivityRepository {
  final pending = Completer<void>();
  int attempts = 0;
  @override
  Future<void> apply(String id, {String? experienceId}) async {
    attempts++;
    await pending.future;
    await super.apply(id, experienceId: experienceId);
  }
}

void main() {
  testWidgets('favorite persists when detail is reopened without applying', (
    t,
  ) async {
    final r = FakeActivityRepository();
    await mount(t, ActivityDetailPage(programId: 'program', repository: r));
    await tap(t, find.byTooltip('관심 프로그램 저장'));
    expect(r.favorites, {'program'});
    expect(r.applyCalls, 0);
    await mount(t, ActivityDetailPage(programId: 'program', repository: r));
    expect(find.byTooltip('관심 프로그램 해제'), findsOneWidget);
    await tap(t, find.byTooltip('관심 프로그램 해제'));
    expect(r.favorites, isEmpty);
    await finish(t);
  });
  testWidgets(
    'missing required preferences cannot write and 20km remains available',
    (t) async {
      final r = FakeActivityRepository();
      await mount(t, ActivityPreferencesPage(repository: r));
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '필수 항목을 골라 주세요'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, find.text('20km'));
      expect(r.saveCalls, 0);
      await finish(t);
    },
  );
  testWidgets(
    'experience list toggles persisted availability without losing content',
    (t) async {
      final r = FakeActivityRepository();
      await r.experience({
        'title': '스마트폰 안내',
        'description': '친절하게 스마트폰을 알려드려요',
        'category': '배움·디지털',
        'active': true,
        'available_time': '오후',
        'activity_type': '대면',
        'preferred_place': '복지관',
      });
      await mount(
        t,
        ActivitySectionPage(
          section: ActivitySection.myExperiences,
          repository: r,
        ),
      );
      await tap(t, find.byType(SwitchListTile));
      expect(r.offers.single['active'], false);
      expect(r.offers.single['description'], '친절하게 스마트폰을 알려드려요');
      await finish(t);
    },
  );
  testWidgets('inactive or different category experience cannot be submitted', (
    t,
  ) async {
    final r = FakeActivityRepository()..addSupport();
    r.offers.addAll([
      {
        'id': 'inactive',
        'title': '쉬는 경험',
        'active': false,
        'category': '건강·운동',
        'available_time': '오전',
      },
      {
        'id': 'other',
        'title': '다른 분야 경험',
        'active': true,
        'category': '문화·취미',
        'available_time': '오후',
      },
    ]);
    await mount(
      t,
      ActivitySupportPage(program: r.programs.last, repository: r),
    );
    await tap(t, find.text('쉬는 경험'));
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '다음 · 제출 내용 확인'),
          )
          .onPressed,
      isNull,
    );
    expect(r.applyCalls, 0);
    await finish(t);
  });
  testWidgets(
    'single mission picker changes only the selected unstarted stage',
    (t) async {
      final r = FakeActivityRepository()..pref = {'place_name': '동네'};
      r.programs.add({...r.programs.first, 'id': 'other', 'title': '다른 산책'});
      r.missions.add({
        'stage': 1,
        'program_id': 'program',
        'program': r.programs.first,
        'status': 'unstarted',
      });
      await mount(
        t,
        ActivitySectionPage(section: ActivitySection.missions, repository: r),
      );
      await tap(t, find.text('바꾸기'));
      await tap(t, find.text('다른 산책'));
      await tap(t, find.text('이 프로그램으로 바꾸기'));
      expect(r.missions.single['program_id'], 'other');
      expect(r.applyCalls, 0);
      expect(r.rebuildCalls, 0);
      await finish(t);
    },
  );
  testWidgets(
    'completed program mission reward refreshes claim status and is not paid twice',
    (t) async {
      final r = FakeActivityRepository()..pref = {'place_name': '동네'};
      r.missions.add({
        'stage': 1,
        'week_start': '2026-10-26',
        'program_id': 'program',
        'program': r.programs.first,
        'status': 'completed',
      });
      await mount(
        t,
        ActivitySectionPage(section: ActivitySection.missions, repository: r),
      );
      await tap(t, find.text('미션 보상 받기'));
      expect(find.text('1단계 보상을 받았어요!'), findsOneWidget);
      await tap(t, find.text('확인'));
      expect(find.text('✓ 미션 보상 지급 완료'), findsOneWidget);
      expect(r.missionRewards.single['points'], 50);
      expect((await r.claimProgramMission(1))['already'], true);
      expect(r.missionRewards.length, 1);
      await finish(t);
    },
  );
  testWidgets(
    'expired benefits remain visible and are not presented as active',
    (t) async {
      final r = FakeActivityRepository();
      r.benefits.add({
        'expires_at': DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
      });
      await mount(
        t,
        ActivitySectionPage(section: ActivitySection.mine, repository: r),
      );
      await tap(t, find.text('혜택'));
      await visible(t, find.text('만료'));
      expect(find.text('지난 혜택'), findsOneWidget);
      expect(find.text('적용 중'), findsNothing);
      await finish(t);
    },
  );
  testWidgets(
    'pending submission blocks duplicate taps and clears processing after completion',
    (t) async {
      final r = PendingApplyRepository();
      await mount(t, ActivityDetailPage(programId: 'program', repository: r));
      await tap(t, find.text('신청하기'));
      await t.tap(find.text('신청하기').last);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('처리하고 있어요'), findsOneWidget);
      expect(r.attempts, 1);
      r.pending.complete();
      await t.pumpAndSettle();
      expect(find.text('신청했어요!'), findsOneWidget);
      expect(find.text('처리하고 있어요'), findsNothing);
      await finish(t);
    },
  );
  testWidgets(
    'weekly mission keeps sequential claims and uses shared controller',
    (t) async {
      final pet = PetPreviewController()..adopt('콩이');
      pet.missions.addAll([
        {
          'stage': 1,
          'progress': 3,
          'target': 3,
          'completed': true,
          'claimed': false,
        },
        {
          'stage': 2,
          'progress': 1,
          'target': 1,
          'completed': true,
          'claimed': false,
        },
        {
          'stage': 3,
          'progress': 1,
          'target': 1,
          'completed': true,
          'claimed': false,
        },
      ]);
      await mount(t, ActivityWeeklyMissionsPage(pet: pet));
      expect(find.text('보상 받기'), findsOneWidget);
      await tap(t, find.text('보상 받기'));
      expect(pet.missions.first['claimed'], true);
      expect(pet.missions[1]['claimed'], false);
      await tap(t, find.text('닫기'));
      await finish(t);
      pet.dispose();
    },
  );
  testWidgets(
    'render reference states and validate narrow large-text layouts',
    (t) async {
      await t.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.runAsync(() async {
        await (FontLoader('Pretendard')
              ..addFont(rootBundle.load('assets/fonts/Pretendard-Regular.otf')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      final r = FakeActivityRepository()
        ..pref = {
          'place_name': '흑석동 집',
          'radius_km': 3,
          'transport': '도보',
          'interests': ['건강·운동'],
        };
      r.programs.first.addAll({
        'title': '건강 체조 교실',
        'org_name': '흑석동 노인복지관',
        'preparations': '편한 운동복, 운동화, 물',
        'target_audience': '만 60세 이상 동작구 주민',
        'floor_guide': '1층 입구 → 엘리베이터 → 2층 강당',
        'fee': 0,
      });
      await r.experience({
        'title': '스마트폰 사용법 알려드리기',
        'description': '30년 동안 경험한 스마트폰과 디지털 도구 사용법을 차근차근 알려드려요',
        'category': '배움·디지털',
        'available_time': '수 오후',
        'preferred_place': '복지관',
        'activity_type': '대면',
        'active': true,
      });
      r.missions.add({
        'stage': 1,
        'week_start': '2026-10-26',
        'program': r.programs.first,
        'program_id': 'program',
        'status': 'unstarted',
      });
      final pet = PetPreviewController()..adopt('콩이');
      pet.missions.addAll([
        {
          'stage': 1,
          'progress': 3,
          'target': 3,
          'completed': true,
          'claimed': false,
        },
        {
          'stage': 2,
          'progress': 0,
          'target': 1,
          'completed': false,
          'claimed': false,
        },
        {
          'stage': 3,
          'progress': 0,
          'target': 1,
          'completed': false,
          'claimed': false,
        },
      ]);
      final screens = <String, Widget>{
        'preview-recommendations': ActivitySectionPage(
          section: ActivitySection.find,
          repository: r,
        ),
        'preview-programs': ActivitySectionPage(
          section: ActivitySection.programs,
          repository: r,
        ),
        'preview-detail': ActivityDetailPage(
          programId: 'program',
          repository: r,
        ),
        'preview-experience-hub': ActivitySectionPage(
          section: ActivitySection.experience,
          repository: r,
        ),
        'preview-experiences': ActivitySectionPage(
          section: ActivitySection.myExperiences,
          repository: r,
        ),
        'preview-program-missions': ActivitySectionPage(
          section: ActivitySection.missions,
          repository: r,
        ),
        'preview-weekly-missions': ActivityWeeklyMissionsPage(pet: pet),
      };
      final destination = Platform.environment['ACTIVITY_V2_PREVIEW_DIR'];
      for (final e in screens.entries) {
        final key = GlobalKey();
        await mount(t, RepaintBoundary(key: key, child: e.value));
        expect(t.takeException(), isNull);
        if (destination != null) {
          await t.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final im = await boundary.toImage(pixelRatio: 2);
            final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
            await Directory(destination).create(recursive: true);
            await File('$destination/${e.key}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            im.dispose();
          });
        }
      }
      await finish(t);
      await t.binding.setSurfaceSize(const Size(320, 900));
      for (final page in [
        ActivitySectionPage(section: ActivitySection.mine, repository: r),
        ActivityWeeklyMissionsPage(pet: pet),
        ActivityDetailPage(programId: 'program', repository: r),
      ]) {
        await mount(t, page, scale: 2);
        expect(t.takeException(), isNull);
        await finish(t);
      }
      pet.dispose();
    },
  );
}
