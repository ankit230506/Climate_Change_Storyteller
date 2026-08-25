import 'dart:io';
import 'package:climate_storyteller/features/lg_connection/lg_overlays.dart';

void main() {
  final dir = Directory('assets/images');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  final regions = [
    {'id': 'arctic', 'name': 'Arctic Circle', 'category': 'glacier'},
    {'id': 'himalaya', 'name': 'Himalaya', 'category': 'glacier'},
    {'id': 'amazon', 'name': 'Amazon Basin', 'category': 'forest'},
    {'id': 'pacific', 'name': 'Pacific Islands', 'category': 'sealevel'},
    {'id': 'sahara', 'name': 'Sahara', 'category': 'heat'},
    {'id': 'maldives', 'name': 'Maldives', 'category': 'sealevel'},
    {'id': 'delhi', 'name': 'Delhi NCR', 'category': 'aqi'},
  ];

  for (final r in regions) {
    final bytes = LGOverlays.createRegionBannerPng(
      r['id']!,
      r['name']!,
      r['category']!,
    );
    final file = File('assets/images/${r['id']}.png');
    file.writeAsBytesSync(bytes);
  }

  final logoBytes = LGOverlays.createLgLogoPng();
  final logoFile = File('assets/images/lg_logo.png');
  logoFile.writeAsBytesSync(logoBytes);
}
