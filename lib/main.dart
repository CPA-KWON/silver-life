import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'auth/auth_gate.dart';

// Provide these at build/run time, e.g.:
// flutter run --dart-define-from-file=.env.json
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
final _supabaseConfigured = _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

// From NAVER Cloud Platform console (Services > Maps). Facility search will
// not work until this is provided, but the rest of the app doesn't need it.
const _naverMapClientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_supabaseConfigured) {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabaseAnonKey,
    );
  }

  if (_naverMapClientId.isNotEmpty) {
    await FlutterNaverMap().init(
      clientId: _naverMapClientId,
      onAuthFailed: (ex) => debugPrint('Naver Map auth failed: $ex'),
    );
  }

  runApp(const SilverLifeApp());
}

class SilverLifeApp extends StatelessWidget {
  const SilverLifeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '실버라이프',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: seniorFriendlyTheme,
      home: _supabaseConfigured
          ? const AuthGate()
          : const _SupabaseNotConfiguredPage(),
    );
  }
}

class _SupabaseNotConfiguredPage extends StatelessWidget {
  const _SupabaseNotConfiguredPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Supabase 설정이 없습니다.\n'
            '--dart-define-from-file=.env.json 옵션으로 실행해주세요.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

