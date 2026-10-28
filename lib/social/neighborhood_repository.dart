import 'package:supabase_flutter/supabase_flutter.dart';

typedef SocialData = Map<String, dynamic>;

class NeighborhoodRepository {
  NeighborhoodRepository({SupabaseClient? client})
    : client = client ?? Supabase.instance.client;
  final SupabaseClient client;
  String get uid => client.auth.currentUser!.id;
  Future<Map<String, SocialData>> states(List<String> ids) async {
    if (ids.isEmpty) return {};
    final result = <String, SocialData>{};
    // Caller lists may exceed RPC batch limits; keep all pages.
    for (var i = 0; i < ids.length; i += 500) {
      final rows = await client.rpc(
        'neighborhood_state',
        params: {'post_ids': ids.skip(i).take(500).toList()},
      );
      for (final r in rows as List) {
        result['${r['id']}'] = Map<String, dynamic>.from(r);
      }
    }
    return result;
  }

  Future<bool> enrich(List<SocialData> rows) async {
    try {
      final extra = await states(rows.map((p) => '${p['id']}').toList());
      for (final p in rows) {
        p.addAll(extra[p['id']] ?? {});
      }
      return true;
    } on PostgrestException catch (e) {
      if (['PGRST202', '42883', '42P01'].contains(e.code)) return false;
      rethrow;
    }
  }

  Future<void> participate(String id, bool value) => client.rpc(
    'meetup_participate',
    params: {'target': id, 'participating': value},
  );
  Future<void> like(String id, bool value) async {
    if (value) {
      await client.from('post_likes').upsert({'user_id': uid, 'post_id': id});
    } else {
      await client
          .from('post_likes')
          .delete()
          .eq('user_id', uid)
          .eq('post_id', id);
    }
  }

  Future<void> block(String id) async {
    if (id == uid) throw StateError('본인은 차단할 수 없어요');
    await client.from('user_blocks').upsert({'user_id': uid, 'blocked_id': id});
  }

  Future<void> unblock(String id) => client
      .from('user_blocks')
      .delete()
      .eq('user_id', uid)
      .eq('blocked_id', id);
  Future<List<SocialData>> blocks() async {
    final b = await client
        .from('user_blocks')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    if (b.isEmpty) return [];
    final profiles = await client
        .from('public_profiles')
        .select('id,nickname')
        .inFilter('id', b.map((x) => x['blocked_id']).toList());
    return [
      for (final row in b)
        {
          ...row,
          'nickname':
              profiles
                  .where((p) => p['id'] == row['blocked_id'])
                  .firstOrNull?['nickname'] ??
              '탈퇴한 사용자',
        },
    ];
  }
}
