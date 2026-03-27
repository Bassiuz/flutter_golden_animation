import 'dart:io';
import 'dart:typed_data';

import '../apng/chunks.dart';

/// Result of comparing two PNG frames.
class FrameComparisonResult {
  FrameComparisonResult({
    required this.passed,
    required this.diffPercent,
    required this.diffPixels,
    required this.totalPixels,
  });

  final bool passed;
  final double diffPercent;
  final int diffPixels;
  final int totalPixels;
}

/// Compares two PNG frames pixel-by-pixel.
///
/// [tolerance] is the maximum allowed diff percentage (0.0 = pixel-perfect).
FrameComparisonResult compareFrames(
  Uint8List expectedPng,
  Uint8List actualPng, {
  double tolerance = 0.0,
}) {
  final expectedPixels = decodePngToRgba(expectedPng);
  final actualPixels = decodePngToRgba(actualPng);

  if (expectedPixels.length != actualPixels.length) {
    return FrameComparisonResult(
      passed: false,
      diffPercent: 100.0,
      diffPixels: expectedPixels.length ~/ 4,
      totalPixels: expectedPixels.length ~/ 4,
    );
  }

  final totalPixels = expectedPixels.length ~/ 4;
  int diffPixels = 0;

  for (int i = 0; i < expectedPixels.length; i += 4) {
    if (expectedPixels[i] != actualPixels[i] ||
        expectedPixels[i + 1] != actualPixels[i + 1] ||
        expectedPixels[i + 2] != actualPixels[i + 2] ||
        expectedPixels[i + 3] != actualPixels[i + 3]) {
      diffPixels++;
    }
  }

  final diffPercent =
      totalPixels > 0 ? (diffPixels / totalPixels) * 100.0 : 0.0;

  return FrameComparisonResult(
    passed: diffPercent <= tolerance,
    diffPercent: diffPercent,
    diffPixels: diffPixels,
    totalPixels: totalPixels,
  );
}

/// Decodes a PNG file to raw RGBA pixel data.
///
/// Handles PNG row filters (None, Sub, Up, Average, Paeth).
/// Only supports 8-bit RGBA PNGs (bit depth 8, color type 6).
Uint8List decodePngToRgba(Uint8List pngBytes) {
  final chunks = parsePngChunks(pngBytes);
  final ihdr = chunks.firstWhere((c) => c.type == 'IHDR');
  final ihdrView = ByteData.sublistView(ihdr.data);
  final width = ihdrView.getUint32(0);
  final height = ihdrView.getUint32(4);
  final bitDepth = ihdr.data[8];
  final colorType = ihdr.data[9];

  if (bitDepth != 8 || colorType != 6) {
    throw FormatException(
      'Only 8-bit RGBA PNGs supported (got bitDepth=$bitDepth, colorType=$colorType)',
    );
  }

  // Concatenate all IDAT data and decompress
  final compressedBuilder = BytesBuilder();
  for (final chunk in chunks.where((c) => c.type == 'IDAT')) {
    compressedBuilder.add(chunk.data);
  }
  final decompressed = Uint8List.fromList(
    ZLibCodec().decode(compressedBuilder.toBytes()),
  );

  final bytesPerPixel = 4;
  final stride = width * bytesPerPixel;
  final pixels = Uint8List(height * stride);

  for (int y = 0; y < height; y++) {
    final filterByte = decompressed[y * (stride + 1)];
    final rowStart = y * (stride + 1) + 1;
    final outStart = y * stride;

    for (int x = 0; x < stride; x++) {
      final raw = decompressed[rowStart + x];
      final a = x >= bytesPerPixel ? pixels[outStart + x - bytesPerPixel] : 0;
      final b = y > 0 ? pixels[outStart + x - stride] : 0;
      final c_ = (x >= bytesPerPixel && y > 0)
          ? pixels[outStart + x - stride - bytesPerPixel]
          : 0;

      switch (filterByte) {
        case 0:
          pixels[outStart + x] = raw;
        case 1:
          pixels[outStart + x] = (raw + a) & 0xFF;
        case 2:
          pixels[outStart + x] = (raw + b) & 0xFF;
        case 3:
          pixels[outStart + x] = (raw + ((a + b) >> 1)) & 0xFF;
        case 4:
          pixels[outStart + x] = (raw + _paeth(a, b, c_)) & 0xFF;
        default:
          throw FormatException('Unknown PNG filter type: $filterByte');
      }
    }
  }

  return pixels;
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}
