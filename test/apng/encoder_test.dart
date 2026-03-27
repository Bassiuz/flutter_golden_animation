import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/apng/encoder.dart';
import 'package:flutter_golden_animation/src/apng/chunks.dart';
import '../helpers/test_png.dart';

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
