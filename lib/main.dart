import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_gate.dart';

// Provide these at build/run time, e.g.:
// flutter run --dart-define-from-file=.env.json
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
final _supabaseConfigured = _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_supabaseConfigured) {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabaseAnonKey,
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
        // Larger baseline text sizes for readability by senior users.
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 18),
          bodyMedium: TextStyle(fontSize: 16),
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
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

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('실버라이프'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: const Center(child: Text('주변 시설 찾기 · 실버 커뮤니티')),
    );
  }
}
