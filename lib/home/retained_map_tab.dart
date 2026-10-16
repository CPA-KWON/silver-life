import 'package:flutter/material.dart';

/// Creates the native map on its first visit, then keeps only that tab alive.
/// Other tabs still reload on entry, as they did before map retention.
class RetainedMapTab extends StatefulWidget {
  const RetainedMapTab({
    super.key,
    required this.selected,
    required this.mapBuilder,
    required this.child,
  });

  final bool selected;
  final Widget Function(BuildContext context, bool active) mapBuilder;
  final Widget child;

  @override
  State<RetainedMapTab> createState() => _RetainedMapTabState();
}

class _RetainedMapTabState extends State<RetainedMapTab> {
  bool _visited = false;

  @override
  Widget build(BuildContext context) {
    _visited |= widget.selected;
    return IndexedStack(
      index: widget.selected ? 1 : 0,
      children: [
        widget.child,
        TickerMode(
          enabled: widget.selected,
          child: _visited
              ? widget.mapBuilder(context, widget.selected)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
