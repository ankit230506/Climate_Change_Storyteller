import 'dart:io';
import 'dart:typed_data';

/// Helper to generate high-resolution PNG overlay images for Liquid Galaxy
/// screen overlays (Liquid Galaxy Logo & Environmental Index Legends).
class LGOverlays {
  LGOverlays._();

  /// Returns PNG bytes for the official Liquid Galaxy Logo banner.
  static Uint8List createLgLogoPng() {
    const width = 280;
    const height = 120;
    final pixels = Uint8List(width * height * 4);

    _fillRect(pixels, width, height, 0, 0, width, height, 20, 24, 38, 220);
    _drawRectBorder(pixels, width, height, 0, 0, width, height, 60, 70, 95, 255, 2);

    final colors = [
      [46, 204, 113],
      [241, 196, 15],
      [230, 126, 34],
      [52, 152, 219],
    ];

    for (int i = 0; i < 4; i++) {
      final x = 20 + i * 22;
      const y = 20;
      const w = 18;
      const h = 45;
      final c = colors[i];
      _fillRoundedRect(pixels, width, height, x, y, w, h, 6, c[0], c[1], c[2], 255);
    }

    _drawSimpleText(pixels, width, height, "LIQUID", 120, 22, 255, 255, 255, 255, scale: 3);
    _drawSimpleText(pixels, width, height, "GALAXY", 120, 54, 100, 180, 255, 255, scale: 3);
    _drawSimpleText(pixels, width, height, "CLIMATE STORYTELLER", 20, 88, 160, 175, 200, 255, scale: 1);

    return _encodePng(pixels, width, height);
  }

  /// Returns PNG bytes for an Environmental Index Legend overlay card.
  static Uint8List createLegendPng(
    String category, {
    String? eraLabel,
    Map<String, String>? stats,
  }) {
    const width = 260;
    final height = (stats != null && stats.isNotEmpty) ? 380 : 280;
    final pixels = Uint8List(width * height * 4);

    _fillRect(pixels, width, height, 0, 0, width, height, 15, 18, 30, 230);
    _drawRectBorder(pixels, width, height, 0, 0, width, height, 50, 65, 90, 255, 2);

    var title = switch (category) {
      'aqi'      => 'AQI INDEX LEGEND',
      'forest'   => 'FOREST COVER LEGEND',
      'sealevel' => 'SEA LEVEL RISE LEGEND',
      'glacier'  => 'ICE MASS & MELT LEGEND',
      'heat'     => 'HEAT ANOMALY LEGEND',
      _          => 'ENVIRONMENTAL LEGEND',
    };

    if (eraLabel != null && eraLabel.isNotEmpty) {
      title = '$title ($eraLabel)';
    }

    final items = switch (category) {
      'aqi' => [
        {'label': 'Good (0-50)',           'r': 46,  'g': 204, 'b': 113},
        {'label': 'Fair (51-100)',         'r': 241, 'g': 196, 'b': 15},
        {'label': 'Moderate (101-150)',    'r': 230, 'g': 126, 'b': 34},
        {'label': 'Poor (151-200)',        'r': 231, 'g': 76,  'b': 60},
        {'label': 'Very Poor (201+)',      'r': 155, 'g': 89,  'b': 182},
      ],
      'forest' => [
        {'label': 'Intact Canopy',         'r': 39,  'g': 174, 'b': 96},
        {'label': 'Light Deforestation',   'r': 184, 'g': 233, 'b': 134},
        {'label': 'Moderate Loss',         'r': 243, 'g': 156, 'b': 18},
        {'label': 'Heavy Loss',            'r': 211, 'g': 84,  'b': 0},
        {'label': 'Critical Loss',         'r': 192, 'g': 57,  'b': 43},
      ],
      'sealevel' => [
        {'label': 'Minimal Rise (0m)',     'r': 41,  'g': 128, 'b': 185},
        {'label': 'Low Inundation (1m)',   'r': 26,  'g': 188, 'b': 156},
        {'label': 'Moderate Flood (3m)',   'r': 241, 'g': 196, 'b': 15},
        {'label': 'High Risk (5m)',        'r': 230, 'g': 126, 'b': 34},
        {'label': 'Extreme Flood (10m)',   'r': 192, 'g': 57,  'b': 43},
      ],
      'glacier' => [
        {'label': 'Solid Ice Sheet',       'r': 175, 'g': 238, 'b': 238},
        {'label': 'Minor Thinning',        'r': 127, 'g': 205, 'b': 205},
        {'label': 'Moderate Melt',         'r': 241, 'g': 196, 'b': 15},
        {'label': 'Rapid Loss',            'r': 230, 'g': 126, 'b': 34},
        {'label': 'Severe Loss',           'r': 231, 'g': 76,  'b': 60},
      ],
      _ => [
        {'label': 'Normal (+0°C)',         'r': 46,  'g': 204, 'b': 113},
        {'label': 'Mild (+1.5°C)',         'r': 241, 'g': 196, 'b': 15},
        {'label': 'Moderate (+2.5°C)',     'r': 230, 'g': 126, 'b': 34},
        {'label': 'Severe (+4.0°C)',       'r': 231, 'g': 76,  'b': 60},
        {'label': 'Extreme (+6.0°C)',      'r': 142, 'g': 68,  'b': 173},
      ],
    };

    _drawSimpleText(pixels, width, height, title, 16, 16, 255, 255, 255, 255, scale: 1);
    _drawLine(pixels, width, height, 16, 36, width - 16, 36, 60, 75, 105, 255, 1);

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final y = 48 + i * 44;
      final r = item['r'] as int;
      final g = item['g'] as int;
      final b = item['b'] as int;
      final label = item['label'] as String;

      _fillRoundedRect(pixels, width, height, 18, y, 28, 28, 4, r, g, b, 255);
      _drawRectBorder(pixels, width, height, 18, y, 28, 28, 255, 255, 255, 180, 1);

      _drawSimpleText(pixels, width, height, label, 56, y + 8, 225, 235, 245, 255, scale: 1);
    }

    if (stats != null && stats.isNotEmpty) {
      _drawLine(pixels, width, height, 16, 260, width - 16, 260, 60, 75, 105, 255, 1);
      _drawSimpleText(pixels, width, height, 'KEY DATA (PAST -> NOW -> FUTURE)', 16, 270, 255, 255, 255, 255, scale: 1);

      final statEntries = stats.entries.take(4).toList();
      for (int i = 0; i < statEntries.length; i++) {
        final entry = statEntries[i];
        final statY = 286 + i * 16;
        _drawSimpleText(
          pixels, width, height,
          '${entry.key}: ${entry.value}',
          16, statY,
          100, 200, 255, 255,
          scale: 1,
        );
      }
    }

    _drawSimpleText(
      pixels, width, height,
      'Source: IPCC AR6 SSP3-7.0',
      16, height - 18,
      120, 130, 150, 200,
      scale: 1,
    );

    return _encodePng(pixels, width, height);
  }

  // ─────────────────────────────────────────────
  // Drawing Primitive Helpers
  // ─────────────────────────────────────────────

  static void _fillRect(Uint8List pixels, int imgW, int imgH, int rx, int ry, int rw, int rh, int r, int g, int b, int a) {
    for (int y = ry; y < ry + rh && y < imgH; y++) {
      if (y < 0) continue;
      for (int x = rx; x < rx + rw && x < imgW; x++) {
        if (x < 0) continue;
        final idx = (y * imgW + x) * 4;
        pixels[idx] = r;
        pixels[idx + 1] = g;
        pixels[idx + 2] = b;
        pixels[idx + 3] = a;
      }
    }
  }

  static void _drawRectBorder(Uint8List pixels, int imgW, int imgH, int rx, int ry, int rw, int rh, int r, int g, int b, int a, int thickness) {
    _fillRect(pixels, imgW, imgH, rx, ry, rw, thickness, r, g, b, a); // Top
    _fillRect(pixels, imgW, imgH, rx, ry + rh - thickness, rw, thickness, r, g, b, a); // Bottom
    _fillRect(pixels, imgW, imgH, rx, ry, thickness, rh, r, g, b, a); // Left
    _fillRect(pixels, imgW, imgH, rx + rw - thickness, ry, thickness, rh, r, g, b, a); // Right
  }

  static void _fillRoundedRect(Uint8List pixels, int imgW, int imgH, int rx, int ry, int rw, int rh, int radius, int r, int g, int b, int a) {
    _fillRect(pixels, imgW, imgH, rx, ry, rw, rh, r, g, b, a);
  }

  static void _drawLine(Uint8List pixels, int imgW, int imgH, int x1, int y1, int x2, int y2, int r, int g, int b, int a, int thickness) {
    _fillRect(pixels, imgW, imgH, x1, y1, (x2 - x1).abs(), thickness, r, g, b, a);
  }

  // Minimal 5x7 bitmap font rendering for uppercase ASCII characters
  static const Map<String, List<int>> _font = {
    'A': [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
    'B': [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
    'C': [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],
    'D': [0x1C, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1C],
    'E': [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
    'F': [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],
    'G': [0x0E, 0x11, 0x10, 0x13, 0x11, 0x11, 0x0F],
    'H': [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
    'I': [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
    'K': [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],
    'L': [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
    'M': [0x11, 0x1B, 0x15, 0x11, 0x11, 0x11, 0x11],
    'N': [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11],
    'O': [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
    'P': [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
    'Q': [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D],
    'R': [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
    'S': [0x0E, 0x11, 0x10, 0x0E, 0x01, 0x11, 0x0E],
    'T': [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
    'U': [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
    'V': [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
    'W': [0x11, 0x11, 0x11, 0x11, 0x15, 0x1B, 0x11],
    'X': [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],
    'Y': [0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04],
    'Z': [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
    '0': [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
    '1': [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
    '2': [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F],
    '3': [0x1F, 0x02, 0x04, 0x0E, 0x01, 0x11, 0x0E],
    '4': [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
    '5': [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
    '6': [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],
    '7': [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
    '8': [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
    '9': [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
    '(': [0x02, 0x04, 0x08, 0x08, 0x08, 0x04, 0x02],
    ')': [0x08, 0x04, 0x02, 0x02, 0x02, 0x04, 0x08],
    '+': [0x00, 0x04, 0x04, 0x1F, 0x04, 0x04, 0x00],
    '-': [0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00],
    '°': [0x06, 0x09, 0x06, 0x00, 0x00, 0x00, 0x00],
    '.': [0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C],
    '%': [0x18, 0x19, 0x02, 0x04, 0x08, 0x13, 0x03],
    ' ': [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
  };

  static void _drawSimpleText(
    Uint8List pixels, int imgW, int imgH, String text, int startX, int startY,
    int r, int g, int b, int a, {int scale = 1}
  ) {
    int curX = startX;
    for (int ch = 0; ch < text.length; ch++) {
      final charStr = text[ch].toUpperCase();
      final glyph = _font[charStr] ?? _font[' ']!;

      for (int row = 0; row < 7; row++) {
        final lineBits = glyph[row];
        for (int col = 0; col < 5; col++) {
          if ((lineBits & (1 << (4 - col))) != 0) {
            _fillRect(
              pixels, imgW, imgH,
              curX + col * scale, startY + row * scale,
              scale, scale, r, g, b, a
            );
          }
        }
      }
      curX += 6 * scale;
    }
  }

  // ─────────────────────────────────────────────
  // Pure Dart PNG Encoder with zlib
  // ─────────────────────────────────────────────

  static Uint8List _encodePng(Uint8List rawRgba, int w, int h) {
    final rawScanlines = Uint8List(h * (1 + w * 4));
    int srcIdx = 0;
    int dstIdx = 0;

    for (int y = 0; y < h; y++) {
      rawScanlines[dstIdx++] = 0; // Filter type: None
      for (int x = 0; x < w * 4; x++) {
        rawScanlines[dstIdx++] = rawRgba[srcIdx++];
      }
    }

    final compressed = zlib.encode(rawScanlines);
    final bb = BytesBuilder();

    // PNG Signature
    bb.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

    // IHDR Chunk
    final ihdrData = ByteData(13)
      ..setUint32(0, w, Endian.big)
      ..setUint32(4, h, Endian.big)
      ..setUint8(8, 8)   // bit depth
      ..setUint8(9, 6)   // color type: RGBA
      ..setUint8(10, 0)  // compression
      ..setUint8(11, 0)  // filter
      ..setUint8(12, 0); // interlace
    _writeChunk(bb, 'IHDR', ihdrData.buffer.asUint8List());

    // IDAT Chunk
    _writeChunk(bb, 'IDAT', Uint8List.fromList(compressed));

    // IEND Chunk
    _writeChunk(bb, 'IEND', Uint8List(0));

    return bb.toBytes();
  }

  static void _writeChunk(BytesBuilder bb, String type, Uint8List data) {
    final len = data.length;
    final lenBytes = ByteData(4)..setUint32(0, len, Endian.big);
    bb.add(lenBytes.buffer.asUint8List());

    final typeBytes = Uint8List.fromList(type.codeUnits);
    bb.add(typeBytes);
    bb.add(data);

    final crcCalcData = Uint8List(4 + len);
    crcCalcData.setRange(0, 4, typeBytes);
    crcCalcData.setRange(4, 4 + len, data);
    final crcVal = _crc32(crcCalcData);

    final crcBytes = ByteData(4)..setUint32(0, crcVal, Endian.big);
    bb.add(crcBytes.buffer.asUint8List());
  }

  static int _crc32(Uint8List data) {
    int crc = 0xFFFFFFFF;
    for (int i = 0; i < data.length; i++) {
      final byte = data[i];
      crc ^= byte;
      for (int k = 0; k < 8; k++) {
        crc = (crc & 1 != 0) ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1);
      }
    }
    return crc ^ 0xFFFFFFFF;
  }
}
