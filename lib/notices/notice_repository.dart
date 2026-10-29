import 'package:supabase_flutter/supabase_flutter.dart';

typedef NoticeData = Map<String, dynamic>;

class NoticeRepository {
  NoticeRepository({this.supabase});
  final SupabaseClient? supabase;
  SupabaseClient get client => supabase ?? Supabase.instance.client;
  Future<List<NoticeData>> feed() async =>
      List<NoticeData>.from(await client.rpc('institution_notice_feed'));
  Future<List<NoticeData>> managed() async =>
      List<NoticeData>.from(await client.rpc('institution_notice_list'));
  Future<NoticeData> detail(String id) async => Map<String, dynamic>.from(
    await client.rpc('institution_notice_detail', params: {'p_id': id}),
  );
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
