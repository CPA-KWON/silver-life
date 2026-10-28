import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silver_life/pet/pet_preview_controller.dart';
import 'package:silver_life/activity/activity_hub_page.dart';
import 'package:silver_life/activity/activity_map_page.dart';
import 'package:silver_life/activity/activity_forms.dart';
import 'package:silver_life/activity/activity_detail_page.dart';
import 'package:silver_life/activity/activity_agency_page.dart';
import 'package:silver_life/activity/activity_support_page.dart';

import 'support/fake_activity_repository.dart';
import 'support/widget_actions.dart';

Future<void> choosePlace(WidgetTester t) async {
  await tap(t, find.text('기준 장소를 골라 주세요'));
  await tap(t, find.text('지도에서 장소 찾기'));
}

Future<void> writeExperience(WidgetTester t) async {
  await fill(t, '나눌 경험', '산책 안내');
  await tap(t, find.text('건강·운동'));
  await fill(t, '경험 설명', '동네에서 산책 모임을 10년 동안 운영했어요');
  await tap(t, find.text('오전'));
  await fill(t, '선호 장소', '동네 공원');
  await tap(t, find.text('대면'));
}

Future<void> rejectReason(WidgetTester t) async {
  await tap(t, find.text('가벼운 산책'));
  await tap(t, find.widgetWithText(FilledButton, '반려'));
  await t.enterText(find.byType(TextField).last, '정원이 모두 찼어요');
  await tap(t, find.widgetWithText(FilledButton, '반려하기'));
}

void main() {
  testWidgets('independent pages retry without losing existing navigation', (
    t,
  ) async {
    final r = FakeActivityRepository()..fail = true;
    await mount(
      t,
      ActivityHubPage(
        repository: r,
        petController: PetPreviewController()..ready = true,
      ),
    );
    await tap(t, find.text('맞춤 활동 찾기'));
    expect(find.text('다시 시도'), findsOneWidget);
    r.fail = false;
    await tap(t, find.text('다시 시도'));
    await tap(t, find.text('전체 프로그램 탐색'));
    expect(find.text('가벼운 산책'), findsOneWidget);
    await mount(
      t,
      ActivitySectionPage(
        section: ActivitySection.myExperiences,
        repository: r,
      ),
    );
    expect(find.text('아직 등록한 경험이 없어요.'), findsOneWidget);
    await mount(
      t,
      ActivitySectionPage(section: ActivitySection.mine, repository: r),
    );
    expect(find.text('아직 신청한 활동이 없어요.'), findsOneWidget);
    await finish(t);
  });
  testWidgets('mission create and rebuild preserve explicit confirmation', (
    t,
  ) async {
    final r = FakeActivityRepository()..pref = {'place_name': '동네'};
    await mount(
      t,
      ActivitySectionPage(section: ActivitySection.missions, repository: r),
    );
    await tap(t, find.text('이번 주 미션 만들기'));
    expect(r.planCalls, 1);
    await tap(t, find.text('신청 전 미션 다시 고르기'));
    await tap(t, find.text('취소'));
    expect(r.rebuildCalls, 0);
    await tap(t, find.text('신청 전 미션 다시 고르기'));
    await tap(t, find.text('확인'));
    expect(r.rebuildCalls, 1);
    expect(find.textContaining('1단계 · 익숙한 동네'), findsOneWidget);
    await finish(t);
  });
  testWidgets('segmented preferences use real place and preserve all options', (
    t,
  ) async {
    final r = FakeActivityRepository();
    await mount(
      t,
      ActivityPreferencesPage(
        repository: r,
        placePicker: (_) async => testPlace,
      ),
    );
    await choosePlace(t);
    await tap(t, find.text('문화·취미'));
    await tap(t, find.text('5km'));
    await tap(t, find.text('대중교통'));
    await tap(t, find.text('함께'));
    await tap(t, find.text('1시간'));
    await tap(t, find.text('보통'));
    await tap(t, find.byType(SwitchListTile));
    await tap(t, find.text('저장하고 추천 보기'));
    expect(r.pref!['place_name'], '테스트 복지관');
    expect(r.pref!['interests'], ['문화·취미']);
    expect(r.pref!['radius_km'], 5);
    expect(r.pref!['transport'], '대중교통');
    expect(r.pref!['participation'], '함께');
    expect(r.pref!['max_minutes'], 60);
    expect(r.pref!['difficulty'], 2);
    expect(r.pref!['expand_choices'], false);
    await finish(t);
  });
  testWidgets(
    'experience create and edit preserve optional values and paused status',
    (t) async {
      final r = FakeActivityRepository();
      await mount(t, ActivityExperiencePage(repository: r));
      await writeExperience(t);
      await tap(t, find.text('저장하기'));
      expect(r.offers.single['title'], '산책 안내');
      expect(r.offers.single['available_time'], '오전');
      final existing = Map<String, dynamic>.from(r.offers.single);
      await mount(t, ActivityExperiencePage(repository: r, existing: existing));
      await tap(t, find.byType(SwitchListTile));
      await tap(t, find.text('저장하기'));
      expect(r.offers.single['active'], false);
      expect(r.offers.single['available_time'], '오전');
      expect(r.offers.single['activity_type'], '대면');
      await finish(t);
    },
  );
  testWidgets('paid application receipt and cancel keep server quoted fee', (
    t,
  ) async {
    final r = FakeActivityRepository()..benefit = true;
    await mount(t, ActivityDetailPage(programId: 'program', repository: r));
    await tap(t, find.text('신청하기'));
    expect(find.text('2501원'), findsOneWidget);
    await tap(t, find.text('취소'));
    expect(r.applyCalls, 0);
    await tap(t, find.text('신청하기'));
    await tap(t, find.text('신청하기').last);
    expect(r.applyCalls, 1);
    expect(find.text('신청했어요!'), findsOneWidget);
    expect(r.applications.single['final_fee'], 2501);
    await tap(t, find.text('프로그램 상세로 돌아가기'));
    await tap(t, find.text('신청 취소'));
    await tap(t, find.text('그대로 두기'));
    expect(r.cancelCalls, 0);
    await tap(t, find.text('신청 취소'));
    await tap(t, find.text('신청 취소하기'));
    expect(r.cancelCalls, 1);
    expect(r.applications.single['status'], 'cancelled');
    await finish(t);
  });
  testWidgets('map uses program coordinates and returns to same detail', (
    t,
  ) async {
    final r = FakeActivityRepository();
    await mount(
      t,
      ActivityDetailPage(
        programId: 'program',
        repository: r,
        mapPlaceholder: const Center(child: Text('지도 검증 영역')),
      ),
    );
    await tap(t, find.text('지도 보기'));
    final page = t.widget<ActivityMapPage>(find.byType(ActivityMapPage));
    expect(page.program['lat'], 37.5666);
    expect(page.program['lng'], 126.979);
    await tap(t, find.text('활동 상세로 돌아가기'));
    expect(find.text('프로그램 상세'), findsOneWidget);
    expect(r.applyCalls, 0);
    await finish(t);
  });
  testWidgets('invalid coordinates cannot open misleading map', (t) async {
    final r = FakeActivityRepository();
    r.programs.first['lat'] = 100;
    await mount(t, ActivityDetailPage(programId: 'program', repository: r));
    await t.scrollUntilVisible(
      find.text('지도 보기'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      t.widget<TextButton>(find.widgetWithText(TextButton, '지도 보기')).onPressed,
      isNull,
    );
    await finish(t);
  });
  testWidgets('full and closed activity cannot submit', (t) async {
    final r = FakeActivityRepository();
    r.programs.first['enrolled'] = 10;
    await mount(t, ActivityDetailPage(programId: 'program', repository: r));
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, '정원이 모두 찼어요'))
          .onPressed,
      isNull,
    );
    r.programs.first['status'] = 'closed';
    await mount(t, ActivityDetailPage(programId: 'program', repository: r));
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, '모집이 마감됐어요'))
          .onPressed,
      isNull,
    );
    expect(r.applyCalls, 0);
    await finish(t);
  });
  testWidgets(
    'support wizard registers experience and submits selected snapshot plus note',
    (t) async {
      final r = FakeActivityRepository()..addSupport();
      await mount(t, ActivityDetailPage(programId: 'support', repository: r));
      await tap(t, find.text('이 모집에 지원하기'));
      expect(find.byType(ActivitySupportPage), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '다음 · 제출 내용 확인'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, find.text('새 경험 등록하고 지원'));
      await writeExperience(t);
      await tap(t, find.text('저장하기'));
      await tap(t, find.text('산책 안내'));
      await t.enterText(find.byType(TextField).last, '수요일 오후 가능해요');
      await t.pumpAndSettle();
      await tap(t, find.text('다음 · 제출 내용 확인'));
      expect(find.text('산책 안내'), findsOneWidget);
      await tap(t, find.text('지원하기'));
      await tap(t, find.text('지원하기').last);
      expect(r.lastNote, '수요일 오후 가능해요');
      expect(r.applications.single['experience_snapshot']['title'], '산책 안내');
      expect(find.text('지원했어요!'), findsOneWidget);
      await finish(t);
    },
  );
  testWidgets(
    'agency approval, reasoned rejection and completion remain connected',
    (t) async {
      final r = FakeActivityRepository()..manager = true;
      r.programs.first['ends_at'] = DateTime.now()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      await r.apply('program');
      const orgs = [
        {'id': 'org', 'name': '복지관'},
      ];
      await mount(
        t,
        ActivityAgencyPage(
          section: AgencySection.applications,
          organizations: orgs,
          repository: r,
        ),
      );
      await rejectReason(t);
      await tap(t, find.text('취소'));
      expect(r.manageCalls, 0);
      await tap(t, find.widgetWithText(FilledButton, '승인하기'));
      await tap(t, find.widgetWithText(FilledButton, '승인하기'));
      expect(r.lastAction, 'approved');
      await tap(t, find.text('참여 예정'));
      await tap(t, find.text('가벼운 산책'));
      await tap(t, find.text('실제 활동 완료 확인'));
      await tap(t, find.widgetWithText(FilledButton, '참여 완료 확인'));
      expect(r.lastAction, 'completed');
      await mount(
        t,
        ActivityAgencyPage(
          section: AgencySection.programs,
          organizations: orgs,
          repository: r,
        ),
      );
      await tap(t, find.text('모집 마감'));
      await tap(t, find.widgetWithText(FilledButton, '모집 마감'));
      expect(r.closeCalls, 1);
      await finish(t);
    },
  );
  testWidgets(
    'program form submits place dates and structured visitor guidance',
    (t) async {
      final r = FakeActivityRepository();
      var i = 0;
      final dates = [
        DateTime.now().add(const Duration(days: 2)),
        DateTime.now().add(const Duration(days: 2, hours: 1)),
        DateTime.now().add(const Duration(days: 1)),
      ];
      await mount(
        t,
        ActivityProgramForm(
          organizations: const [
            {'id': 'org', 'name': '복지관'},
          ],
          repository: r,
          placePicker: (_) async => testPlace,
          datePicker: (_, _) async => dates[i++],
        ),
      );
      await fill(t, '프로그램 이름', '새 프로그램');
      await fill(t, '활동 안내', '동네 활동 안내');
      await fill(t, '대상', '만 60세 이상');
      await fill(t, '준비물', '신분증');
      await fill(t, '층별 안내', '1층 → 엘리베이터 → 2층 강당');
      await tap(t, find.text('활동 장소 선택'));
      for (final title in ['활동 시작', '활동 종료', '모집 마감']) {
        await tap(t, find.textContaining(title));
      }
      await tap(t, find.text('등록하기'));
      expect(r.saveCalls, 1);
      expect(r.programs.last['place_name'], '테스트 복지관');
      expect(r.programs.last['preparations'], '신분증');
      await finish(t);
    },
  );
  testWidgets('program form without institution cannot save', (t) async {
    await mount(
      t,
      ActivityProgramForm(
        organizations: const [],
        repository: FakeActivityRepository(),
      ),
    );
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, '등록하기'))
          .onPressed,
      isNull,
    );
    await finish(t);
  });
  testWidgets('small screen and large text keep new forms usable', (t) async {
    await t.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final r = FakeActivityRepository();
    await mount(t, ActivityPreferencesPage(repository: r), scale: 2);
    await tap(t, find.byType(SwitchListTile));
    expect(t.takeException(), isNull);
    await finish(t);
  });
  testWidgets('date/time dialogs support cancel and confirm', (t) async {
    DateTime? picked;
    await mount(
      t,
      Builder(
        builder: (c) => TextButton(
          onPressed: () async {
            picked = await pickActivityDate(c, null);
          },
          child: const Text('일정 선택'),
        ),
      ),
    );
    await tap(t, find.text('일정 선택'));
    await tap(t, find.text('취소'));
    expect(picked, isNull);
    await tap(t, find.text('일정 선택'));
    await tap(t, find.text('확인'));
    await tap(t, find.text('확인'));
    expect(picked, isNotNull);
    await finish(t);
  });
  testWidgets('agency reason is visible to applicant only after confirmation', (
    t,
  ) async {
    final r = FakeActivityRepository();
    await r.apply('program');
    await mount(
      t,
      ActivityAgencyPage(
        section: AgencySection.applications,
        organizations: const [
          {'id': 'org', 'name': '복지관'},
        ],
        repository: r,
      ),
    );
    await rejectReason(t);
    await tap(t, find.widgetWithText(FilledButton, '반려하기'));
    expect(r.lastAction, 'rejected');
    expect(r.applications.single['rejection_reason'], '정원이 모두 찼어요');
    expect(r.benefit, false);
    await finish(t);
  });
}
