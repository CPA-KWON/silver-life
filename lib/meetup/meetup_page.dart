import 'package:flutter/material.dart';

import '../social/neighborhood_feed.dart';

class MeetupPage extends StatelessWidget {
  const MeetupPage({super.key, this.active = true});
  final bool active;
  @override
  Widget build(BuildContext context) =>
      NeighborhoodFeed(meetup: true, active: active);
}
