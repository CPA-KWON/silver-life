import 'package:flutter/material.dart';

import '../social/neighborhood_feed.dart';

class MeetupPage extends StatelessWidget {
  const MeetupPage({super.key});
  @override
  Widget build(BuildContext context) => const NeighborhoodFeed(meetup: true);
}
