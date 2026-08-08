import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:climate_storyteller/features/lg_connection/lg_overlays.dart';

void main() {
  group('LGOverlays.createLegendPng', () {
    test('creates default legend PNG without optional parameters', () {
      final bytes = LGOverlays.createLegendPng('forest');
      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, isTrue);
    });

    test('creates legend PNG with eraLabel', () {
      final bytes = LGOverlays.createLegendPng('forest', eraLabel: '2100');
      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, isTrue);
    });

    test('creates legend PNG with stats and increases height', () {
      final bytes = LGOverlays.createLegendPng(
        'forest',
        eraLabel: '2100',
        stats: {
          'Tree Loss': '15.4%',
          'CO2 Impact': '+420ppm',
          'Temp Rise': '+2.4C',
          'Status': 'Critical',
          'Ignored5th': 'Extra',
        },
      );
      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, isTrue);
    });
  });
}
