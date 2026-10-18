import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/nearby_facilities.dart';
import '../activity/activity_widgets.dart';
import '../ui/design_widgets.dart';
import 'facility_search_page.dart';
import 'naver_local_search.dart';

Future<void> openSavedFacility(BuildContext context, FacilityResult result) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('시설 찾기')),
          body: FacilitySearchPage(
            initialFacility: result,
            showDetailBackButton: false,
          ),
        ),
      ),
    );

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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('즐겨찾는 시설')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (s.hasError)
                ActivityInfo('즐겨찾는 시설을 불러오지 못했어요.', onRetry: reload)
              else if (s.data!.isEmpty)
                const ActivityInfo('아직 즐겨찾는 시설이 없어요.')
              else
                for (final p in s.data!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SectionCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(p['name']),
                        subtitle: Text(p['address'] ?? ''),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await openSavedFacility(
                            context,
                            FacilityResult(
                              name: p['name'],
                              address: p['address'] ?? '',
                              telephone: p['telephone'] ?? '',
                              lat: (p['lat'] as num).toDouble(),
                              lng: (p['lng'] as num).toDouble(),
                              category: p['category'] ?? '',
                              distanceMeters: double.nan,
                            ),
                          );
                          if (mounted) await reload();
                        },
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    ),
  );
}
