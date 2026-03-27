import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/apng/decoder.dart';
import 'package:flutter_golden_animation/src/apng/encoder.dart';
import 'package:flutter_golden_animation/src/apng/chunks.dart';
import '../helpers/test_png.dart';

void main() {
  group('ApngDecoder', () {
    test('decodes single-frame APNG', () {
      final frame = createTestPng();
      final apng = encodeApng(frames: [frame], frameDelayMs: 100);

      final result = decodeApng(apng);

      expect(result.frames.length, equals(1));
      expect(result.frameDelayMs, equals(100));
    });

    test('decodes multi-frame APNG with correct frame count', () {
      final frames = [
        createTestPng(red: 255),
        createTestPng(green: 255),
        createTestPng(blue: 255),
      ];
      final apng = encodeApng(frames: frames, frameDelayMs: 50);

      final result = decodeApng(apng);

      expect(result.frames.length, equals(3));
      expect(result.frameDelayMs, equals(50));
    });

    test('decoded frames are valid PNGs', () {
      final original = createTestPng(red: 128, green: 64, blue: 32);
      final apng = encodeApng(frames: [original], frameDelayMs: 100);

      final result = decodeApng(apng);
      final decodedFrame = result.frames[0];

      // Should start with PNG signature
      expect(decodedFrame.sublist(0, 8), equals(pngSignature));
      // Should be parseable
      final chunks = parsePngChunks(decodedFrame);
      expect(chunks.map((c) => c.type), containsAll(['IHDR', 'IDAT', 'IEND']));
    });

    test('throws on non-APNG PNG (no acTL chunk)', () {
      final plainPng = createTestPng();
      expect(
        () => decodeApng(plainPng),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
