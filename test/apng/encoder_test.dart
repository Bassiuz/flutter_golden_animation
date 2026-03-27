import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/apng/encoder.dart';
import 'package:flutter_golden_animation/src/apng/chunks.dart';

/// Creates a minimal valid 1x1 red RGBA PNG for testing.
Uint8List createTestPng({int red = 255, int green = 0, int blue = 0, int alpha = 255}) {
  final builder = BytesBuilder();
  builder.add(pngSignature);

  // IHDR: 1x1, 8-bit RGBA
  final ihdrData = Uint8List(13);
  final ihdrView = ByteData.sublistView(ihdrData);
  ihdrView.setUint32(0, 1); // width
  ihdrView.setUint32(4, 1); // height
  ihdrData[8] = 8;  // bit depth
  ihdrData[9] = 6;  // color type RGBA
  ihdrData[10] = 0; // compression
  ihdrData[11] = 0; // filter
  ihdrData[12] = 0; // interlace
  builder.add(PngChunk('IHDR', ihdrData).toBytes());

  // IDAT: zlib-compressed row (filter byte 0 + RGBA pixel)
  final rawRow = Uint8List.fromList([0, red, green, blue, alpha]);
  final compressed = ZLibCodec(level: 0).encode(rawRow);
  builder.add(PngChunk('IDAT', Uint8List.fromList(compressed)).toBytes());

  // IEND
  builder.add(PngChunk('IEND', Uint8List(0)).toBytes());

  return Uint8List.fromList(builder.toBytes());
}

void main() {
  group('ApngEncoder', () {
    test('encodes a single frame as valid APNG', () {
      final frame = createTestPng();
      final apng = encodeApng(
        frames: [frame],
        frameDelayMs: 100,
      );

      // Should start with PNG signature
      expect(apng.sublist(0, 8), equals(pngSignature));

      // Should contain acTL chunk
      final chunks = parsePngChunks(apng);
      final chunkTypes = chunks.map((c) => c.type).toList();
      expect(chunkTypes, contains('acTL'));
      expect(chunkTypes, contains('IHDR'));
      expect(chunkTypes, contains('IEND'));
    });

    test('encodes multiple frames with correct frame count', () {
      final frame1 = createTestPng(red: 255);
      final frame2 = createTestPng(red: 0, green: 255);
      final frame3 = createTestPng(blue: 255);

      final apng = encodeApng(
        frames: [frame1, frame2, frame3],
        frameDelayMs: 100,
      );

      final chunks = parsePngChunks(apng);

      // acTL should report 3 frames
      final acTL = chunks.firstWhere((c) => c.type == 'acTL');
      final acTLView = ByteData.sublistView(acTL.data);
      expect(acTLView.getUint32(0), equals(3)); // num_frames

      // Should have 3 fcTL chunks (one per frame)
      final fcTLCount = chunks.where((c) => c.type == 'fcTL').length;
      expect(fcTLCount, equals(3));
    });

    test('produces deterministic output', () {
      final frame = createTestPng();
      final apng1 = encodeApng(frames: [frame], frameDelayMs: 100);
      final apng2 = encodeApng(frames: [frame], frameDelayMs: 100);

      expect(apng1, equals(apng2));
    });

    test('throws on empty frame list', () {
      expect(
        () => encodeApng(frames: [], frameDelayMs: 100),
        throwsArgumentError,
      );
    });
  });
}
