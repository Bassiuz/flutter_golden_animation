import 'dart:io';
import 'dart:typed_data';

import '../apng/chunks.dart';
import 'frame_comparator.dart';

/// Generates a diff PNG highlighting pixels that differ between two frames.
///
/// Unchanged pixels are shown at 30% opacity (dimmed original).
/// Changed pixels are shown in red (#FF0000) at full opacity.
Uint8List generateDiffImage(Uint8List expectedPng, Uint8List actualPng) {
  final expectedChunks = parsePngChunks(expectedPng);
  final ihdr = expectedChunks.firstWhere((c) => c.type == 'IHDR');
  final ihdrView = ByteData.sublistView(ihdr.data);
  final width = ihdrView.getUint32(0);
  final height = ihdrView.getUint32(4);

  // Use the shared decoder from frame_comparator.dart
  final expectedPixels = decodePngToRgba(expectedPng);
  final actualPixels = decodePngToRgba(actualPng);

  // Build diff pixels
  final diffPixels = Uint8List(width * height * 4);
  for (int i = 0; i < diffPixels.length; i += 4) {
    final different = expectedPixels[i] != actualPixels[i] ||
        expectedPixels[i + 1] != actualPixels[i + 1] ||
        expectedPixels[i + 2] != actualPixels[i + 2] ||
        expectedPixels[i + 3] != actualPixels[i + 3];

    if (different) {
      diffPixels[i] = 255; // R
      diffPixels[i + 1] = 0; // G
      diffPixels[i + 2] = 0; // B
      diffPixels[i + 3] = 255; // A
    } else {
      diffPixels[i] = expectedPixels[i];
      diffPixels[i + 1] = expectedPixels[i + 1];
      diffPixels[i + 2] = expectedPixels[i + 2];
      diffPixels[i + 3] = (expectedPixels[i + 3] * 0.3).round();
    }
  }

  // Encode back to PNG
  return _encodePng(ihdr, diffPixels, width, height);
}

Uint8List _encodePng(
    PngChunk ihdr, Uint8List pixels, int width, int height) {
  final stride = width * 4;

  // Add filter byte (0 = None) to each row
  final rawData = Uint8List(height * (stride + 1));
  for (int y = 0; y < height; y++) {
    rawData[y * (stride + 1)] = 0; // filter = None
    rawData.setRange(
      y * (stride + 1) + 1,
      y * (stride + 1) + 1 + stride,
      pixels,
      y * stride,
    );
  }

  final compressed = Uint8List.fromList(ZLibCodec(level: 0).encode(rawData));

  return buildPng([
    ihdr,
    PngChunk('IDAT', compressed),
    PngChunk('IEND', Uint8List(0)),
  ]);
}
