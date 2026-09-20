import 'package:flutter/material.dart';

/// How narrowly a list of posts is scoped to the viewer's own region.
/// No "전체" (nationwide) option — everything is at least scoped to the
/// viewer's own 시/도.
enum RegionScope { sido, sigungu }

/// Row of two chips (시도 단위 / 시군구 단위) shared by the community and
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: Text(mySido == null ? '시/도' : '$mySido 전체'),
            selected: scope == RegionScope.sido,
            onSelected: onChanged == null ? null : (_) => onChanged!(RegionScope.sido),
          ),
          ChoiceChip(
            label: Text(mySigungu == null ? '시/군/구' : '$mySigungu만'),
            selected: scope == RegionScope.sigungu,
            onSelected: onChanged == null ? null : (_) => onChanged!(RegionScope.sigungu),
          ),
        ],
      ),
    );
  }
}
