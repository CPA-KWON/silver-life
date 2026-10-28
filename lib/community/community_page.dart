import 'package:flutter/material.dart';

import '../social/neighborhood_feed.dart';

const kPostCategories = communityCategories;

class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key});
  @override
  Widget build(BuildContext context) => const NeighborhoodFeed(meetup: false);
}
