import 'package:flutter/material.dart';

import '../facility/facility_repository.dart';

import '../app_theme.dart';
import '../facility/naver_local_search.dart';

/// What the user chose in [showMeetupPlaceSheet]: a favorite facility, or
/// "search on the map" (then [favorite] is null).
class MeetupPlaceChoice {
  const MeetupPlaceChoice.favorite(FacilityResult this.favorite);
  const MeetupPlaceChoice.map() : favorite = null;
  final FacilityResult? favorite;
}

/// Bottom sheet for the meetup "장소" row: lists the user's favorites
/// (`favorites` rows are copies without facility_id, so the result has no
/// id — the meetup save path registers it via ensureFacility) plus a button
/// to open the map picker instead.
Future<MeetupPlaceChoice?> showMeetupPlaceSheet(BuildContext context) =>
    showModalBottomSheet<MeetupPlaceChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _MeetupPlaceSheet(),
    );

class _MeetupPlaceSheet extends StatefulWidget {
  const _MeetupPlaceSheet();

  @override
  State<_MeetupPlaceSheet> createState() => _MeetupPlaceSheetState();
}

class _MeetupPlaceSheetState extends State<_MeetupPlaceSheet> {
  late Future<List<FacilityResult>> _future = loadFavoriteFacilities();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('모임 장소 고르기', style: textTheme.titleLarge),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(const MeetupPlaceChoice.map()),
                icon: const Icon(Icons.map_outlined),
                label: const Text('지도에서 장소 찾기'),
              ),
              const SizedBox(height: 20),
              Text(
                '내가 즐겨찾는 시설',
                style: textTheme.titleMedium?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: FutureBuilder<List<FacilityResult>>(
                  future: _future,
                  builder: (context, s) {
                    if (s.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (s.hasError) {
                      return _Message(
                        '즐겨찾는 시설을 불러오지 못했어요. 다시 시도해 주세요.',
                        onRetry: () => setState(() {
                          _future = loadFavoriteFacilities();
                        }),
                      );
                    }
                    final items = s.data!;
                    if (items.isEmpty) {
                      return const _Message(
                        '아직 즐겨찾는 시설이 없어요.\n'
                        '시설 찾기에서 별 모양 버튼으로 저장할 수 있어요.',
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _FavoriteTile(
                        place: items[i],
                        onTap: () =>
                            Navigator.of(context)
                                .pop(MeetupPlaceChoice.favorite(items[i])),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({required this.place, required this.onTap});
  final FacilityResult place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.tint,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.star, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        style: textTheme.bodyLarge?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (place.address.isNotEmpty)
                        Text(
                          place.address,
                          style: textTheme.bodyMedium?.copyWith(
                            fontSize: 18,
                            color: AppColors.textPrimary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '선택',
                  style: textTheme.bodyLarge?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
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

class _Message extends StatelessWidget {
  const _Message(this.text, {this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(fontSize: 18, color: AppColors.textPrimary),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ],
    ),
  );
}
