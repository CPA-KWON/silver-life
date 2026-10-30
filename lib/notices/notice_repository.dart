import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/neighborhood_region.dart';

typedef NoticeData = Map<String, dynamic>;

NoticeData publicNoticeData(NoticeData row) => {
  ...row,
  'id': 'public-notice:${row['id']}',
  'is_public_source': true,
  'org_name': row['institution_name'],
  'body': row['summary'],
  'published_at': '${row['published_on']}T00:00:00+09:00',
  'important': false,
  'pinned': false,
};

class NoticeRepository {
  NoticeRepository({this.supabase, this.regionResolver});
  final NeighborhoodRegionResolver? regionResolver;
  final SupabaseClient? supabase;
  SupabaseClient get client => supabase ?? Supabase.instance.client;
  Future<NoticeData?>? _preferred;
  String? _preferredUser;
  int preferenceRevision = 0;

  Future<NoticeData?> preferredInstitution() {
    final uid = client.auth.currentUser!.id;
    if (_preferredUser != uid) {
      _preferred = null;
      _preferredUser = uid;
    }
    return _preferred ??= client
        .from('my_notice_institutions')
        .select()
        .eq('user_id', uid)
        .maybeSingle()
        .timeout(const Duration(seconds: 8))
        .catchError((Object e) {
          _preferred = null;
          throw e;
        });
  }

  Future<List<NoticeData>> institutions() async => List<NoticeData>.from(
    await client
        .from('public_notice_institutions')
        .select()
        .order('institution_name')
        .timeout(const Duration(seconds: 10)),
  );

  Future<void> selectInstitution(NoticeData institution) async {
    await client
        .from('my_notice_institutions')
        .upsert({
          'user_id': client.auth.currentUser!.id,
          'institution_name': institution['institution_name'],
          'region_sido': institution['region_sido'],
          'region_sigungu': institution['region_sigungu'],
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .timeout(const Duration(seconds: 10));
    _preferred = null;
    preferenceRevision++;
  }

  Future<List<NoticeData>> homeFeed() async {
    NoticeData? preferred;
    try {
      preferred = await preferredInstitution();
    } catch (_) {
      return feed();
    }
    return preferred == null ? feed() : publicFeed(institution: preferred);
  }

  Future<List<NoticeData>> feed() async {
    final region = await (regionResolver ?? NeighborhoodRegionResolver.shared)
        .resolve();
    return _combined(region: region);
  }

  Future<List<NoticeData>> browse({
    bool archive = false,
    bool allRegions = false,
  }) async {
    if (!archive && !allRegions) return feed();
    final region = allRegions
        ? defaultNeighborhood
        : await (regionResolver ?? NeighborhoodRegionResolver.shared).resolve();
    if (archive) {
      return publicFeed(archive: true, allRegions: allRegions, region: region);
    }
    return _combined(region: region, allRegions: true);
  }

  Future<List<NoticeData>> _combined({
    required NeighborhoodRegion region,
    bool allRegions = false,
  }) async {
    List<NoticeData>? partner, external;
    Object? failure;
    await Future.wait([
      () async {
        try {
          partner = await _partnerFeed(region, allRegions: allRegions);
        } catch (e) {
          failure = e;
        }
      }(),
      () async {
        try {
          external = await publicFeed(region: region, allRegions: allRegions);
        } catch (e) {
          failure ??= e;
        }
      }(),
    ]);
    if (partner == null && external == null) {
      throw failure ?? StateError('공지 연결 실패');
    }
    if (failure != null &&
        (partner?.isEmpty ?? true) &&
        (external?.isEmpty ?? true)) {
      throw failure!;
    }
    final rows = [...?partner, ...?external];
    rows.sort((a, b) {
      for (final key in ['pinned', 'important']) {
        final order = (b[key] == true ? 1 : 0).compareTo(
          a[key] == true ? 1 : 0,
        );
        if (order != 0) return order;
      }
      return (DateTime.tryParse('${b['published_at']}') ?? DateTime(1970))
          .compareTo(
            DateTime.tryParse('${a['published_at']}') ?? DateTime(1970),
          );
    });
    return rows;
  }

  Future<List<NoticeData>> _partnerFeed(
    NeighborhoodRegion region, {
    bool allRegions = false,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    // Explicitly public columns only. Staff RLS also permits drafts, so apply
    // publication, schedule, expiry and approved-organization filters here.
    var query = client
        .from('institution_notices')
        .select(
          'id,org_id,title,body,region_sido,region_sigungu,source_url,published_at,important,pinned,institution_kind,activity_organizations!inner(name,approved)',
        )
        .eq('published', true)
        .eq('activity_organizations.approved', true);
    if (!allRegions) {
      query = query
          .eq('region_sido', region.sido)
          .eq('region_sigungu', region.sigungu);
    }
    final rows = await query
        .or('publish_at.is.null,publish_at.lte.$now')
        .or('expires_at.is.null,expires_at.gt.$now')
        .order('pinned', ascending: false)
        .order('important', ascending: false)
        .order('published_at', ascending: false)
        .limit(50);
    return [
      for (final row in rows)
        {
          ...row,
          'org_name': row['activity_organizations']?['name'],
          'summary': '${row['body'] ?? ''}'.length <= 140
              ? '${row['body'] ?? ''}'
              : '${row['body']}'.substring(0, 140),
        },
    ];
  }

  Future<List<NoticeData>> publicFeed({
    bool archive = false,
    bool allRegions = false,
    NeighborhoodRegion? region,
    NoticeData? institution,
  }) async {
    if (institution != null) {
      region = (
        sido: '${institution['region_sido']}',
        sigungu: '${institution['region_sigungu']}',
      );
    } else {
      region ??= allRegions
          ? defaultNeighborhood
          : await (regionResolver ?? NeighborhoodRegionResolver.shared)
                .resolve();
    }
    final cutoff = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 9))
        .subtract(const Duration(days: 60))
        .toIso8601String()
        .split('T')
        .first;
    final result = <NoticeData>[];
    for (var offset = 0; ; offset += 500) {
      var query = client
          .from('public_institution_notices')
          .select()
          .eq('published', true);
      if (institution != null) {
        query = query
            .eq('institution_name', institution['institution_name'])
            .eq('region_sido', institution['region_sido'])
            .eq('region_sigungu', institution['region_sigungu']);
      } else if (!allRegions) {
        query = query
            .eq('region_sido', region.sido)
            .eq('region_sigungu', region.sigungu);
      }
      query = archive
          ? query.or('archived.eq.true,published_on.lt.$cutoff')
          : query.eq('archived', false).gte('published_on', cutoff);
      final page = await query
          .order('published_on', ascending: false)
          .order('id')
          .range(offset, offset + 499)
          .timeout(const Duration(seconds: 10));
      result.addAll(page.map(publicNoticeData));
      if (page.length < 500) break;
    }
    return result;
  }

  Future<List<NoticeData>> managed() async =>
      List<NoticeData>.from(await client.rpc('institution_notice_list'));
  Future<NoticeData> detail(String id) async {
    if (id.startsWith('public-notice:')) {
      final row = await client
          .from('public_institution_notices')
          .select()
          .eq('id', id.substring('public-notice:'.length))
          .single()
          .timeout(const Duration(seconds: 10));
      return publicNoticeData(row);
    }
    return Map<String, dynamic>.from(
      await client.rpc('institution_notice_detail', params: {'p_id': id}),
    );
  }

  Future<String> save(NoticeData data, {String? id}) async => await client.rpc(
    'institution_notice_save_v2',
    params: {'p_data': data, 'p_id': id},
  ) as String;
  Future<void> publish(String id, bool value) => client.rpc(
    'institution_notice_publish',
    params: {'p_id': id, 'p_published': value},
  );
  Future<List<NoticeData>> programs(String org) async => List<NoticeData>.from(
    await client.from('activity_programs').select().eq('org_id', org),
  ).where((p) => p['draft'] != true).toList();
  Future<NoticeData> region() async => await client
      .from('profiles')
      .select('region_sido,region_sigungu')
      .eq('id', client.auth.currentUser!.id)
      .single();
}
