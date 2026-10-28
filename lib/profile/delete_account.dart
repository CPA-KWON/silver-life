import 'package:flutter/material.dart';

import 'extra_settings_pages.dart';

Future<void> confirmAccountDeletion(BuildContext context) async {
  await Navigator.of(context)
      .push<void>(MaterialPageRoute(builder: (_) => const DeleteAccountPage()));
}
