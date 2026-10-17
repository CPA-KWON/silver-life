import 'package:silver_life/activity/activity_repository.dart';

class FakeActivityRepository extends ActivityRepository {
  FakeActivityRepository();
  final programs = <ActivityData>[
    {
      'id': 'program',
      'org_id': 'org',
      'org_name': '동네 복지관',
      'title': '가벼운 산책',
      'description': '동네에서 천천히 걸어요.',
      'category': activityCategories.first,
      'kind': 'activity',
      'place_name': '동네 공원',
      'fee': 5001,
      'capacity': 10,
      'enrolled': 0,
      'sponsored': true,
      'distance_km': 0.3,
      'difficulty': 1,
      'participation': '함께',
      'transports': ['도보'],
      'status': 'open',
      'starts_at': DateTime.now()
          .add(const Duration(days: 2))
          .toIso8601String(),
      'ends_at': DateTime.now()
          .add(const Duration(days: 2, hours: 1))
          .toIso8601String(),
      'deadline': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
    },
  ];
  final offers = <ActivityData>[];
  final applications = <ActivityData>[];
  final missions = <ActivityData>[];
  ActivityData? pref;
  bool fail = false;
  bool manager = false;
  int planCalls = 0,
      rebuildCalls = 0,
      applyCalls = 0,
      cancelCalls = 0,
      saveCalls = 0,
      manageCalls = 0,
      closeCalls = 0;
  String? lastAction;
  bool benefit = false;
  @override
  Future<ActivityData> home() async {
    if (fail) throw StateError('offline');
    return {
      'preferences': pref,
      'programs': programs,
      'recommendations': programs
          .where((p) => p['kind'] == 'activity')
          .toList(),
      'experiences': offers,
      'applications': applications,
      'missions': missions,
      'organizations': manager
          ? [
              {'id': 'org', 'name': '동네 복지관'},
            ]
          : <ActivityData>[],
      'benefit_expires_at': benefit
          ? DateTime.now().add(const Duration(days: 30)).toIso8601String()
          : null,
    };
  }

  @override
  Future<ActivityData> detail(String id) async {
    if (fail) throw StateError('offline');
    final p = programs.firstWhere((p) => p['id'] == id);
    return {
      'program': p,
      'application': applications
          .where((e) => e['program']['id'] == id)
          .firstOrNull,
      'quote': benefit ? ((p['fee'] as int) + 1) ~/ 2 : p['fee'],
    };
  }

  @override
  Future<void> preferences(ActivityData data) async {
    pref = data;
    saveCalls++;
  }

  @override
  Future<void> experience(ActivityData data, {String? id}) async {
    saveCalls++;
    if (id == null) {
      offers.add({...data, 'id': 'offer-${offers.length}'});
    } else {
      offers.firstWhere((o) => o['id'] == id).addAll(data);
    }
  }

  @override
  Future<void> plan({bool rebuild = false}) async {
    planCalls++;
    if (rebuild) rebuildCalls++;
    missions.clear();
    missions.add({
      'stage': 1,
      'program_id': 'program',
      'program': programs.first,
      'status': 'unstarted',
    });
  }

  @override
  Future<void> apply(String id, {String? experienceId}) async {
    applyCalls++;
    final p = programs.firstWhere((p) => p['id'] == id);
    final price = benefit ? ((p['fee'] as int) + 1) ~/ 2 : p['fee'];
    applications.removeWhere((e) => e['program']['id'] == id);
    applications.add({
      'id': 'application',
      'program': p,
      'program_id': id,
      'status': 'applied',
      'final_fee': price,
      'original_fee': p['fee'],
      'experience_snapshot': offers
          .where((o) => o['id'] == experienceId)
          .firstOrNull,
    });
  }

  @override
  Future<void> cancel(String id) async {
    cancelCalls++;
    applications.firstWhere((e) => e['id'] == id)['status'] = 'cancelled';
  }

  @override
  Future<ActivityData> agency() async => {
    'programs': programs,
    'applications': applications,
    'metrics': {
      'completed': 0,
      'participants': 0,
      'categories': 0,
      'repeat_participants': 0,
    },
  };
  @override
  Future<void> program(ActivityData data) async {
    saveCalls++;
    programs.add({
      ...data,
      'id': 'created',
      'org_name': '동네 복지관',
      'enrolled': 0,
      'sponsored': false,
      'status': 'open',
    });
  }

  @override
  Future<void> manage(String id, String action) async {
    manageCalls++;
    lastAction = action;
    applications.firstWhere((e) => e['id'] == id)['status'] = action;
  }

  @override
  Future<void> close(String id) async {
    closeCalls++;
    programs.firstWhere((p) => p['id'] == id)['status'] = 'closed';
  }

  void addSupport() {
    programs.add({
      ...programs.first,
      'id': 'support',
      'title': '산책 경험 나눔',
      'kind': 'experience',
      'fee': 0,
      'sponsored': false,
    });
  }
}
