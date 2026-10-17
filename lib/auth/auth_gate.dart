import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/main_shell.dart';
import 'login_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, this.signedInPage = const MainShell()});
  final Widget signedInPage;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        auth.currentSession,
      ),
      builder: (context, snapshot) {
        final session = snapshot.hasData
            ? snapshot.data!.session
            : auth.currentSession;
        // All signed-in routes belong to this user. Replacing this Navigator
        // also removes pushed profile/detail pages when the session ends.
        return _SessionNavigator(
          key: ValueKey(session?.user.id ?? 'signed-out'),
          home: session == null ? const LoginPage() : signedInPage,
        );
      },
    );
  }
}

class _SessionNavigator extends StatefulWidget {
  const _SessionNavigator({super.key, required this.home});
  final Widget home;

  @override
  State<_SessionNavigator> createState() => _SessionNavigatorState();
}

class _SessionNavigatorState extends State<_SessionNavigator> {
  final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => NavigatorPopHandler<Object?>(
    onPopWithResult: (_) => navigatorKey.currentState!.pop(),
    child: Navigator(
      key: navigatorKey,
      onGenerateRoute: (_) =>
          MaterialPageRoute<void>(builder: (_) => widget.home),
    ),
  );
}
