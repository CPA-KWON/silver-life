import 'package:flutter/material.dart';

import '../app_theme.dart';

/// How narrowly a list of posts is scoped to the viewer's own region.
/// No "전체" (nationwide) option — everything is at least scoped to the
/// viewer's own 시/도.
enum RegionScope { sido, sigungu }

/// Two-segment control (시도 단위 / 시군구 단위) shared by the community and
/// meetup tabs.
class RegionScopeBar extends StatelessWidget {
  const RegionScopeBar({
    super.key,
    required this.scope,
    required this.mySido,
    required this.mySigungu,
    required this.onChanged,
  });

  final RegionScope scope;
  final String? mySido;
  final String? mySigungu;
  final ValueChanged<RegionScope>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.segmentTrack,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          // IntrinsicHeight bounds the stretched Row when the bar sits in an
          // unbounded parent (e.g. a ListView), keeping both segments equal.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Segment(
                    label: mySido == null ? '시/도' : '$mySido 전체',
                    selected: scope == RegionScope.sido,
                    onTap: onChanged == null
                        ? null
                        : () => onChanged!(RegionScope.sido),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _Segment(
                    label: mySigungu == null ? '시/군/구' : '$mySigungu만',
                    selected: scope == RegionScope.sigungu,
                    onTap: onChanged == null
                        ? null
                        : () => onChanged!(RegionScope.sigungu),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        enabled: onTap != null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: radius,
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected ? Colors.white : AppColors.scheduleText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
