import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silver_life/home/retained_map_tab.dart';

void main() {
  testWidgets('native map is lazy, retained on revisit and inactive off-tab', (
    tester,
  ) async {
    var builds = 0;
    var disposals = 0;
    Widget page(bool selected) => MaterialApp(
      home: RetainedMapTab(
        selected: selected,
        mapBuilder: (_, active) => _MapProbe(
          active: active,
          onCreated: () => builds++,
          onDisposed: () => disposals++,
        ),
        child: const Text('home'),
      ),
    );
    await tester.pumpWidget(page(false));
    expect(builds, 0);
    await tester.pumpWidget(page(true));
    expect(builds, 1);
    await tester.tap(find.text('map 0'));
    await tester.pump();
    expect(find.text('map 1'), findsOneWidget);
    await tester.pumpWidget(page(false));
    expect(disposals, 0);
    final hidden = tester.widget<_MapProbe>(
      find.byType(_MapProbe, skipOffstage: false),
    );
    expect(hidden.active, isFalse);
    expect(find.text('home'), findsOneWidget);
    await tester.pumpWidget(page(true));
    expect(builds, 1);
    expect(find.text('map 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(disposals, 1);
  });
}

class _MapProbe extends StatefulWidget {
  const _MapProbe({
    required this.active,
    required this.onCreated,
    required this.onDisposed,
  });
  final bool active;
  final VoidCallback onCreated;
  final VoidCallback onDisposed;
  @override
  State<_MapProbe> createState() => _MapProbeState();
}

class _MapProbeState extends State<_MapProbe> {
  int count = 0;
  @override
  void initState() {
    super.initState();
    widget.onCreated();
  }

  @override
  void dispose() {
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: widget.active ? () => setState(() => count++) : null,
    child: Text('map $count'),
  );
}
