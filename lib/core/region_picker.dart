import 'package:flutter/material.dart';

import 'korea_regions.dart';

/// Two dropdowns (시/도 → 시/군/구). Kept as two separate values (not
/// combined into one string) so callers can filter by either granularity —
/// needed for the community/meetup region scope (전체 / 시도 단위 / 시군구
/// 단위) — and because several 시/군/구 names like "중구" repeat across
/// multiple 시/도, so 시군구 alone is never a safe filter key.
class RegionPicker extends StatefulWidget {
  const RegionPicker({
    super.key,
    this.initialSido,
    this.initialSigungu,
    required this.onChanged,
  });

  final String? initialSido;
  final String? initialSigungu;
  final void Function(String sido, String sigungu) onChanged;

  @override
  State<RegionPicker> createState() => _RegionPickerState();
}

class _RegionPickerState extends State<RegionPicker> {
  late String _sido;
  late String _sigungu;

  @override
  void initState() {
    super.initState();
    _sido = kKoreaRegions.containsKey(widget.initialSido)
        ? widget.initialSido!
        : kKoreaRegions.keys.first;
    final options = kKoreaRegions[_sido]!;
    _sigungu = options.contains(widget.initialSigungu)
        ? widget.initialSigungu!
        : options.first;

    if (_sido != widget.initialSido || _sigungu != widget.initialSigungu) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onChanged(_sido, _sigungu);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sigunguOptions = kKoreaRegions[_sido]!;
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _sido,
            decoration: const InputDecoration(labelText: '시/도'),
            items: [
              for (final sido in kKoreaRegions.keys)
                DropdownMenuItem(value: sido, child: Text(sido)),
            ],
            onChanged: (value) {
              setState(() {
                _sido = value!;
                _sigungu = kKoreaRegions[_sido]!.first;
              });
              widget.onChanged(_sido, _sigungu);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _sigungu,
            decoration: const InputDecoration(labelText: '시/군/구'),
            items: [
              for (final sigungu in sigunguOptions)
                DropdownMenuItem(value: sigungu, child: Text(sigungu)),
            ],
            onChanged: (value) {
              setState(() => _sigungu = value!);
              widget.onChanged(_sido, _sigungu);
            },
          ),
        ),
      ],
    );
  }
}
