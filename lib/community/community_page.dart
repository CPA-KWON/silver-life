import 'package:flutter/material.dart';

import '../social/neighborhood_feed.dart';

const kPostCategories = communityCategories;

class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key, this.active = true});
  final bool active;
  @override
  Widget build(BuildContext context) =>
      NeighborhoodFeed(meetup: false, active: active);
}
