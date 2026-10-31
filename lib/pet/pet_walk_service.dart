import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// false = 앱 화면이 켜져 있을 때만 기록하는 첫 출시 방식. 복귀 시간 설정과
/// 알림 권한 요청을 숨긴다. 다시 켜는 방법은 docs/pet_walk_background.md.
const kPetWalkBackground = false;

class PetWalkService {
  static const channel = MethodChannel('silver_life/pet_walk');
  String get owner => Supabase.instance.client.auth.currentUser?.id ?? '';
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<Map<String, dynamic>> status() async {
    if (!supported) return {'supported': false, 'active': false, 'steps': 0};
    return Map<String, dynamic>.from(
      await channel.invokeMethod('status', {'owner': owner}) as Map,
    );
  }

  Future<void> start(
    String session, {
    DateTime? returnAt,
    String? petName,
  }) async {
    if (!supported) throw StateError('현재 기기에서는 걸음 수 기록을 지원하지 않아요.');
    final activity = await Permission.activityRecognition.request();
    final location = await Permission.locationWhenInUse.request();
    if (kPetWalkBackground) await Permission.notification.request();
    if (!activity.isGranted && !location.isGranted) {
      throw StateError('걸음 수 또는 위치 권한을 허용해주세요.');
    }
    await channel.invokeMethod('start', {
      'owner': owner,
      'session': session,
      'return_at': returnAt?.millisecondsSinceEpoch ?? 0,
      'pet_name': petName ?? '반려동물',
    });
  }

  Future<void> configureReturn(DateTime? time, String? name) async {
    if (supported) {
      await channel.invokeMethod('configure', {
        'owner': owner,
        'return_at': time?.millisecondsSinceEpoch ?? 0,
        'pet_name': name ?? '반려동물',
      });
    }
  }

  Future<void> pause() => channel.invokeMethod('pause');
  Future<void> resume() => channel.invokeMethod('resume');
  Future<void> stop() async {
    if (supported) await channel.invokeMethod('stop');
  }
}
