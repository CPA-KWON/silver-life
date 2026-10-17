import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silver_life/activity/activity_hub_page.dart';
import 'package:silver_life/activity/activity_forms.dart';
import 'package:silver_life/activity/activity_detail_page.dart';
import 'package:silver_life/activity/activity_agency_page.dart';

import 'support/fake_activity_repository.dart';
import 'support/widget_actions.dart';

void main() {
  testWidgets(
    'service failure offers working retry and all tabs render empty states',
    (t) async {
      final r = FakeActivityRepository()..fail = true;
      await mount(t, ActivityHubPage(repository: r));
      expect(find.text('다시 시도'), findsOneWidget);
      r.fail = false;
      await tap(t, find.text('다시 시도'));
      await tap(t, find.text('경험 은행'));
      expect(find.text('아직 등록한 경험이 없어요.'), findsOneWidget);
      await tap(t, find.text('전체 활동'));
      expect(find.text('가벼운 산책'), findsOneWidget);
      await tap(t, find.text('내 신청'));
      expect(find.text('아직 신청한 활동이 없어요.'), findsOneWidget);
      await finish(t);
    },
  );
  testWidgets('mission create and safe rebuild buttons invoke repository', (
    t,
  ) async {
    final r = FakeActivityRepository()..pref = {'place_name': '동네'};
    await mount(t, ActivityHubPage(repository: r));
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
  testWidgets('preferences place picker, chips, switch and save', (t) async {
    final r = FakeActivityRepository();
    await mount(
      t,
      ActivityPreferencesPage(
        repository: r,
        placePicker: (_) async => testPlace,
      ),
    );
    await tap(t, find.text('기준 장소 선택'));
    await tap(t, find.text('문화·취미'));
    await tap(t, find.byType(SwitchListTile));
    await tap(t, find.text('저장'));
    expect(r.pref!['place_name'], '테스트 복지관');
    expect(r.pref!['interests'], contains('문화·취미'));
    expect(r.pref!['expand_choices'], false);
    await finish(t);
  });
  testWidgets(
    'experience creation and edit preserve fields and paused status',
    (t) async {
      final r = FakeActivityRepository();
      await mount(t, ActivityExperiencePage(repository: r));
      for (final e in {
        '나눌 경험': '재봉',
        '경험 설명': '옷 수선 경험',
        '가능한 시간': '오전',
        '선호 장소': '복지관',
        '활동 형태': '소규모',
      }.entries) {
        await fill(t, e.key, e.value);
      }
      await tap(t, find.text('저장'));
      expect(r.offers.single['title'], '재봉');
      await mount(
        t,
        ActivityExperiencePage(repository: r, existing: r.offers.single),
      );
      await tap(t, find.byType(SwitchListTile));
      await tap(t, find.text('저장'));
      expect(r.offers.single['active'], false);
      await finish(t);
    },
  );
  testWidgets('paid application confirmation, receipt and cancellation', (
    t,
  ) async {
    final r = FakeActivityRepository()..benefit = true;
    await mount(t, ActivityDetailPage(programId: 'program', repository: r));
    expect(find.textContaining('예상 참여비 2501원'), findsOneWidget);
    await tap(t, find.text('활동 신청'));
    await tap(t, find.text('취소'));
    expect(r.applyCalls, 0);
    await tap(t, find.text('활동 신청'));
    await tap(t, find.text('확인'));
    expect(r.applyCalls, 1);
    expect(find.textContaining('승인 대기'), findsOneWidget);
    await tap(t, find.text('신청 취소'));
    await tap(t, find.text('확인'));
    expect(r.cancelCalls, 1);
    await finish(t);
  });
  testWidgets('full and closed activity cannot submit', (t) async {
    final r = FakeActivityRepository();
    r.programs.first['enrolled'] = 10;
    await mount(t, ActivityDetailPage(programId: 'program', repository: r));
    expect(find.text('정원이 모두 찼어요.'), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, '활동 신청'))
          .onPressed,
      isNull,
    );
    r.programs.first['status'] = 'closed';
    await mount(t, ActivityDetailPage(programId: 'program', repository: r));
    expect(find.text('모집이 마감된 활동이에요.'), findsOneWidget);
    await finish(t);
  });
  testWidgets('experience support registration returns to enabled apply', (
    t,
  ) async {
    final r = FakeActivityRepository()..addSupport();
    await mount(t, ActivityDetailPage(programId: 'support', repository: r));
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, '경험 나눔 지원'))
          .onPressed,
      isNull,
    );
    await tap(t, find.text('이 분야의 경험 등록'));
    for (final e in {
      '나눌 경험': '산책 안내',
      '경험 설명': '산책 모임 운영',
      '가능한 시간': '오전',
      '선호 장소': '공원',
      '활동 형태': '함께',
    }.entries) {
      await fill(t, e.key, e.value);
    }
    await tap(t, find.text('저장'));
    await tap(t, find.text('경험 나눔 지원'));
    await tap(t, find.text('확인'));
    expect(r.applications.single['experience_snapshot']['title'], '산책 안내');
    await finish(t);
  });
  testWidgets('agency approval, rejection cancel and completion buttons', (
    t,
  ) async {
    final r = FakeActivityRepository()..manager = true;
    r.programs.first['ends_at'] = DateTime.now()
        .subtract(const Duration(hours: 1))
        .toIso8601String();
    await r.apply('program');
    await mount(
      t,
      ActivityAgencyPage(
        organizations: const [
          {'id': 'org', 'name': '복지관'},
        ],
        repository: r,
      ),
    );
    await tap(t, find.text('신청 반려'));
    await tap(t, find.text('취소'));
    expect(r.manageCalls, 0);
    await tap(t, find.text('신청 승인'));
    await tap(t, find.text('확인'));
    expect(r.lastAction, 'approved');
    await tap(t, find.text('실제 활동 완료 확인'));
    await tap(t, find.text('확인'));
    expect(r.lastAction, 'completed');
    await tap(t, find.text('가벼운 산책 모집 마감'));
    await tap(t, find.text('확인'));
    expect(r.closeCalls, 1);
    await finish(t);
  });
  testWidgets('program form submits selected place and valid dates', (t) async {
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
        datePicker: (_, initial) async => dates[i++],
      ),
    );
    await fill(t, '프로그램 이름', '새 프로그램');
    await fill(t, '활동 안내', '동네 활동');
    await tap(t, find.text('활동 장소 선택'));
    for (final title in ['활동 시작', '활동 종료', '모집 마감']) {
      await tap(t, find.textContaining(title));
    }
    await tap(t, find.text('저장'));
    expect(r.saveCalls, 1);
    expect(r.programs.last['place_name'], '테스트 복지관');
    await finish(t);
  });
  testWidgets('program form without institutional rights is disabled', (
    t,
  ) async {
    final r = FakeActivityRepository();
    await mount(t, ActivityProgramForm(organizations: const [], repository: r));
    expect(find.text('기관 담당자 권한이 필요해요.'), findsOneWidget);
    expect(
      t.widget<FilledButton>(find.widgetWithText(FilledButton, '저장')).onPressed,
      isNull,
    );
    await finish(t);
  });
  testWidgets('narrow screen and large text keep hub and forms usable', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final r = FakeActivityRepository()..pref = {'place_name': '동네'};
    await mount(t, ActivityHubPage(repository: r), scale: 2);
    await tap(t, find.text('경험 은행'));
    expect(t.takeException(), isNull);
    await mount(t, ActivityPreferencesPage(repository: r), scale: 2);
    await tap(t, find.byType(SwitchListTile));
    expect(t.takeException(), isNull);
    await finish(t);
  });
  testWidgets(
    'preferences dropdowns persist user distance transport and difficulty',
    (t) async {
      final r = FakeActivityRepository();
      await mount(
        t,
        ActivityPreferencesPage(
          repository: r,
          placePicker: (_) async => testPlace,
        ),
      );
      await tap(t, find.text('기준 장소 선택'));
      await tap(t, find.text('3 km'));
      await tap(t, find.text('5 km').last);
      await tap(t, find.text('도보'));
      await tap(t, find.text('대중교통').last);
      await tap(t, find.text('무관'));
      await tap(t, find.text('함께').last);
      await tap(t, find.text('120 분'));
      await tap(t, find.text('60 분').last);
      await tap(t, find.text('쉬움'));
      await tap(t, find.text('보통').last);
      await tap(t, find.text('저장'));
      expect(r.pref!['radius_km'], 5);
      expect(r.pref!['transport'], '대중교통');
      expect(r.pref!['participation'], '함께');
      expect(r.pref!['max_minutes'], 60);
      expect(r.pref!['difficulty'], 2);
      await finish(t);
    },
  );
  testWidgets('actual date and time dialogs support cancel and confirm', (
    t,
  ) async {
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
  testWidgets('agency rejection changes enrollment only after confirmation', (
    t,
  ) async {
    final r = FakeActivityRepository();
    await r.apply('program');
    await mount(
      t,
      ActivityAgencyPage(
        organizations: const [
          {'id': 'org', 'name': '복지관'},
        ],
        repository: r,
      ),
    );
    await tap(t, find.text('신청 반려'));
    await tap(t, find.text('확인'));
    expect(r.lastAction, 'rejected');
    expect(r.benefit, false);
    await finish(t);
  });
}
