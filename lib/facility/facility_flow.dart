import 'package:flutter/material.dart';

import 'naver_local_search.dart';

/// Child activity/community flows reuse the already mounted map when choosing
/// a location. No root navigator transition wraps its native PlatformView.
class FacilityPickerScope extends InheritedWidget {
  const FacilityPickerScope({
    super.key,
    required this.pick,
    required super.child,
  });
  final Future<FacilityResult?> Function() pick;
  static Future<FacilityResult?> Function()? maybeOf(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<FacilityPickerScope>()?.pick;
  @override
  bool updateShouldNotify(FacilityPickerScope old) => pick != old.pick;
}

/// Links saved places back to the single retained native map in MainShell.
class FacilityMapScope extends InheritedWidget {
  const FacilityMapScope({super.key, required this.open, required super.child});
  final void Function(List<FacilityResult> places, bool detail) open;
  static FacilityMapScope? maybeOf(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<FacilityMapScope>();
  @override
  bool updateShouldNotify(FacilityMapScope old) => open != old.open;
}

class FacilityFlow extends StatelessWidget {
  const FacilityFlow({
    super.key,
    required this.navigatorKey,
    required this.page,
    required this.onClose,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget page;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext c) => Navigator(
    key: navigatorKey,
    observers: [_FlowObserver(onClose)],
    onGenerateInitialRoutes: (_, _) => [
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: 'facility-base'),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, a, b) => const SizedBox.shrink(),
      ),
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: 'facility-start'),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, a, b) => page,
      ),
    ],
  );
}

class _FlowObserver extends NavigatorObserver {
  _FlowObserver(this.close);
  final VoidCallback close;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == 'facility-start') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        close();
      });
    }
  }
}
