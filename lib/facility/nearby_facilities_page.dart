import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/nearby_facilities.dart';
import '../ui/neighborhood_design.dart';
import 'facility_result_widgets.dart';
import 'facility_distance.dart';

import 'package:geolocator/geolocator.dart';

import 'facility_search_page.dart';
import 'facility_flow.dart';
import 'naver_local_search.dart';

Future<void> openSavedFacility(
  BuildContext context,
  FacilityResult result,
) async {
  final shared = FacilityMapScope.maybeOf(context);
  if (shared != null) {
    shared.open([result], true);
    return;
  }
  final reuseMap = FacilityPickerScope.maybeOf(context) != null;
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (c, a, b) => reuseMap
          ? FacilityDetailPage(
              result: result,
              onClose: () => Navigator.of(c).pop(),
            )
          : Scaffold(body: FacilitySearchPage(initialFacility: result)),
    ),
  );
}

class NearbyFacilitiesPage extends StatelessWidget {
  const NearbyFacilitiesPage({super.key, this.loader});
  final NearbyLoader? loader;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('내 주변 시설')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        NearbyFacilitiesSection(
          loader: loader,
          onOpenFacility: (result) => openSavedFacility(context, result),
          onShowMap: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

class FavoriteFacilitiesPage extends StatefulWidget {
  const FavoriteFacilitiesPage({super.key});
  @override
  State<FavoriteFacilitiesPage> createState() => _FavoriteFacilitiesPageState();
}

class _FavoriteFacilitiesPageState extends State<FavoriteFacilitiesPage> {
  Position? position;
  @override
  void initState() {
    super.initState();
    loadFacilityPosition().then((p) {
      if (mounted) setState(() => position = p);
    });
  }

  FacilityResult result(Map<String, dynamic> p) => FacilityResult(
    name: p['name'],
    address: p['address'] ?? '',
    telephone: p['telephone'] ?? '',
    lat: (p['lat'] as num).toDouble(),
    lng: (p['lng'] as num).toDouble(),
    category: p['category'] ?? '',
    distanceMeters: double.nan,
  );
  void map(List<Map<String, dynamic>> rows) {
    final places = rows.map(result).toList();
    final scope = FacilityMapScope.maybeOf(context);
    if (scope != null) {
      scope.open(places, false);
      return;
    }
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (c, a, b) => _SavedMapPage(places: places),
      ),
    );
  }

  Future<void> unstar(Map<String, dynamic> p) async {
    if (!await activityDialog(
      context,
      title: '즐겨찾기에서 지울까요?',
      message: p['name'],
      action: '지우기',
      icon: Icons.star_outline,
    )) {
      return;
    }
    try {
      await Supabase.instance.client
          .from('favorites')
          .delete()
          .eq('id', p['id'])
          .eq('user_id', Supabase.instance.client.auth.currentUser!.id);
      if (mounted) await reload();
    } catch (_) {
      if (mounted) await activityFailure(context, title: '즐겨찾기를 지우지 못했어요');
    }
  }

  late Future<List<Map<String, dynamic>>> future = load();
  Future<List<Map<String, dynamic>>> load() async {
    final client = Supabase.instance.client;
    return List<Map<String, dynamic>>.from(
      await client
          .from('favorites')
          .select('id,name,address,telephone,lat,lng,category')
          .eq('user_id', client.auth.currentUser!.id)
          .order('created_at', ascending: false),
    );
  }

  Future<void> reload() async {
    final f = load();
    setState(() {
      future = f;
    });
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => NeighborhoodScreen(
    title: '즐겨찾는 시설',
    tint: const Color(0xFFD6EBFC),
    subtitle: '별을 누른 시설이 모여요. 모임 장소로도 바로 고를 수 있어요.',
    child: FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) {
          return const NeighborhoodLoading();
        }
        final rows = s.data ?? [];
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (s.hasError)
                ActivityEmpty(
                  '즐겨찾는 시설을 불러오지 못했어요.',
                  action: '다시 시도',
                  onAction: reload,
                )
              else if (rows.isEmpty)
                ActivityEmpty(
                  '아직 즐겨찾는 시설이 없어요.',
                  message: '자주 가는 곳을 찾아 별을 눌러 주세요.',
                  icon: Icons.star_outline,
                  action: '시설 찾으러 가기',
                  onAction: () => map([]),
                )
              else ...[
                ActivityCard(
                  child: Column(
                    children: [
                      for (final p in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ActivityCard(
                            padding: 12,
                            border: const BorderSide(color: PetColors.line),
                            onTap: () async {
                              await openSavedFacility(context, result(p));
                              if (mounted) await reload();
                            },
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: facilityColor('${p['category']}')
                                        .withValues(alpha: .12),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(
                                    facilityIcon('${p['category']}'),
                                    color: facilityColor('${p['category']}'),
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(p['name'], style: petText(19)),
                                      const SizedBox(height: 6),
                                      Text(
                                        p['address'] ?? '',
                                        style: petText(
                                          15,
                                          color: PetColors.secondary,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        facilityDistanceLabel(
                                          position == null
                                              ? null
                                              : Geolocator.distanceBetween(
                                                  position!.latitude,
                                                  position!.longitude,
                                                  (p['lat'] as num).toDouble(),
                                                  (p['lng'] as num).toDouble(),
                                                ),
                                        ),
                                        style: petText(
                                          14,
                                          color: PetColors.blue,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: '즐겨찾기 해제',
                                  onPressed: () => unstar(p),
                                  icon: const Icon(
                                    Icons.star,
                                    color: PetColors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ActivityButton(
                  '지도에서 모두 보기',
                  icon: Icons.map_outlined,
                  light: true,
                  onTap: () => map(rows),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

class _SavedMapPage extends StatefulWidget {
  const _SavedMapPage({required this.places});
  final List<FacilityResult> places;
  @override
  State<_SavedMapPage> createState() => _SavedMapState();
}

class _SavedMapState extends State<_SavedMapPage> {
  final mapKey = GlobalKey<FacilitySearchPageState>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.places.isNotEmpty) {
        mapKey.currentState?.showFacilities(widget.places);
      }
    });
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: Text(widget.places.isEmpty ? '시설 찾기' : '즐겨찾는 시설 지도')),
    body: FacilitySearchPage(key: mapKey),
  );
}
