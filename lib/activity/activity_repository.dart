import 'package:supabase_flutter/supabase_flutter.dart';

typedef ActivityData = Map<String, dynamic>;
List<ActivityData> activityRows(dynamic value) => (value as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();
const activityCategories = ['건강·운동', '문화·취미', '배움·디지털', '생활·기술', '지역·이야기'];
const activityStatuses = {
  'applied': '승인 대기',
  'approved': '참여 예정',
  'completed': '참여 완료',
  'cancelled': '신청 취소',
  'rejected': '반려',
  'unstarted': '다음 활동',
};
String activityDate(dynamic value) {
  final d = DateTime.tryParse('$value')?.toLocal();
  return d == null
      ? ''
      : '${d.year}년 ${d.month}월 ${d.day}일 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String activityMoney(dynamic value) =>
    (value as num? ?? 0) == 0 ? '무료' : '$value원';

class ActivityRepository {
  ActivityRepository({this._client});
  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? Supabase.instance.client;
  String get userId => client.auth.currentUser!.id;
  Future<ActivityData> home() async {
    final data = Map<String, dynamic>.from(
      await client.rpc('activity_home') as Map,
    );
    try {
      data['benefits'] = await client
          .from('activity_benefits')
          .select()
          .eq('user_id', userId)
          .order('expires_at', ascending: false);
    } catch (_) {
      // Keep the main response usable if the optional history request fails.
      data['benefits_unavailable'] = true;
    }
    try {
      data['mission_rewards'] = await client
          .from('pet_history')
          .select('reference,points,experience,created_at')
          .eq('user_id', userId)
          .like('reference', 'program-mission:%');
    } catch (_) {
      data['mission_rewards_unavailable'] = true;
    }
    return data;
  }

  Future<ActivityData> detail(String id) async => Map<String, dynamic>.from(
    await client.rpc('activity_program_detail', params: {'program_id': id})
        as Map,
  );
  Future<ActivityData> agency() async =>
      Map<String, dynamic>.from(await client.rpc('activity_agency') as Map);
  Future<void> plan({bool rebuild = false}) async {
    await client.rpc(
      'activity_plan_week',
      params: {'rebuild_unstarted': rebuild},
    );
  }

  Future<ActivityData> applicant() async => Map<String, dynamic>.from(
    await client.from('profiles').select('nickname').eq('id', userId).single(),
  );

  Future<void> preferences(ActivityData data) async {
    await client.from('activity_preferences').upsert({
      ...data,
      'user_id': userId,
    });
  }

  Future<void> experience(ActivityData data, {String? id}) async {
    if (id == null) {
      await client.from('activity_experiences').insert({
        ...data,
        'user_id': userId,
      });
    } else {
      await client
          .from('activity_experiences')
          .update(data)
          .eq('id', id)
          .eq('user_id', userId);
    }
  }

  Future<void> apply(String id, {String? experienceId}) async {
    await client.rpc(
      'activity_apply_with_note',
      params: {
        'target_program': id,
        'target_experience': experienceId,
        'application_note': '',
      },
    );
  }

  Future<void> cancel(String id) async {
    await client.rpc('activity_cancel', params: {'enrollment': id});
  }

  Future<void> applyWithNote(
    String id, {
    required String experienceId,
    String note = '',
  }) async {
    await client.rpc(
      'activity_apply_with_note',
      params: {
        'target_program': id,
        'target_experience': experienceId,
        'application_note': note.trim(),
      },
    );
  }

  Future<bool> isFavorite(String id) async =>
      (await client
              .from('activity_program_favorites')
              .select('program_id')
              .eq('user_id', userId)
              .eq('program_id', id))
          .isNotEmpty;

  Future<void> favorite(String id, bool value) async {
    if (value) {
      await client.from('activity_program_favorites').upsert({
        'user_id': userId,
        'program_id': id,
      });
    } else {
      await client
          .from('activity_program_favorites')
          .delete()
          .eq('user_id', userId)
          .eq('program_id', id);
    }
  }

  Future<List<ActivityData>> missionChoices(int stage) async => activityRows(
    await client.rpc(
      'activity_mission_choices',
      params: {'target_stage': stage},
    ),
  );

  Future<ActivityData> claimProgramMission(int stage) async =>
      Map<String, dynamic>.from(
        await client.rpc(
          'activity_claim_program_mission',
          params: {'target_stage': stage},
        ) as Map,
      );

  Future<void> replaceMission(int stage, String id) async {
    await client.rpc(
      'activity_replace_mission',
      params: {'target_stage': stage, 'target_program': id},
    );
  }

  Future<void> rejectWithReason(String id, String reason) async {
    await client.rpc(
      'activity_reject_with_reason',
      params: {'enrollment': id, 'reason': reason.trim()},
    );
  }

  Future<void> manage(String id, String action) async {
    await client.rpc(
      'activity_manage',
      params: {'enrollment': id, 'action': action},
    );
  }

  Future<void> program(ActivityData data) async {
    await client.rpc(
      [
            'target_audience',
            'preparations',
            'floor_guide',
          ].any((k) => '${data[k] ?? ''}'.trim().isNotEmpty)
          ? 'activity_save_program_v2'
          : 'activity_save_program',
      params: {'data': data},
    );
  }

  Future<void> close(String id) async {
    await client.rpc('activity_close_program', params: {'target_program': id});
  }
}
