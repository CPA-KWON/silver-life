import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

typedef PetJson = Map<String, dynamic>;

/// All wallet and reward mutations are performed by authenticated server RPCs.
class PetRepository {
  PetRepository({SupabaseClient? client})
    : client = client ?? Supabase.instance.client;
  final SupabaseClient client;
  Future<PetJson> load() async =>
      Map<String, dynamic>.from(await client.rpc('pet_state'));
  Future<PetJson> act(String action, PetJson payload, String requestId) async =>
      Map<String, dynamic>.from(
        await client.rpc(
          'pet_action',
          params: {
            'p_action': action,
            'p_payload': payload,
            'p_request': requestId,
          },
        ),
      );
  static String requestId() {
    final r = Random.secure();
    final b = List.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final s = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }
}
