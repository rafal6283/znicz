import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/db.dart';
import '../logic/ics.dart';
import 'common.dart';

/// Eksport rocznic do pliku kalendarza (.ics) – otwiera się w Kalendarzu Google / Apple.
Future<void> exportIcs(BuildContext context) async {
  final people = await AppDb.I.allPeople();
  final views = {for (final v in await AppDb.I.graveViews()) v.grave.id!: v};
  final withDates = people.where((p) => (p.death?.isFull ?? false) || (p.birth?.isFull ?? false)).toList();
  if (withDates.isEmpty) {
    if (context.mounted) snack(context, 'Brak pełnych dat urodzin lub śmierci do dodania');
    return;
  }
  final ics = buildIcs(withDates, whereOf: (p) => views[p.graveId]?.cemetery?.label ?? '');
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/znicz-rocznice.ics');
  await f.writeAsString(ics);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(f.path, mimeType: 'text/calendar')],
    text: 'Rocznice bliskich z aplikacji Znicz – otwórz plik w kalendarzu, żeby je dodać.',
  ));
}
