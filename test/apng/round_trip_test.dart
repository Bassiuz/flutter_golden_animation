import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/apng/encoder.dart';
import 'package:flutter_golden_animation/src/apng/decoder.dart';
import '../helpers/test_png.dart';

void main() {
  group('APNG round-trip', () {
    test('single frame survives encode-decode', () {
      final original = createTestPng(red: 100, green: 150, blue: 200);
      final apng = encodeApng(frames: [original], frameDelayMs: 100);
      final result = decodeApng(apng);

      expect(result.frames.length, equals(1));
      expect(result.frameDelayMs, equals(100));
      // The decoded frame should be byte-identical to the original
      expect(result.frames[0], equals(original));
    });

    test('multiple frames survive encode-decode', () {
      final frames = [
        createTestPng(red: 255, green: 0, blue: 0),
        createTestPng(red: 0, green: 255, blue: 0),
        createTestPng(red: 0, green: 0, blue: 255),
      ];
      final apng = encodeApng(frames: frames, frameDelayMs: 200);
      final result = decodeApng(apng);

      expect(result.frames.length, equals(3));
      expect(result.frameDelayMs, equals(200));
      for (int i = 0; i < 3; i++) {
        expect(result.frames[i], equals(frames[i]));
      }
    });

    test('frame delay is preserved', () {
      final frame = createTestPng();
      final apng = encodeApng(frames: [frame], frameDelayMs: 42);
      final result = decodeApng(apng);
      expect(result.frameDelayMs, equals(42));
    });
  });
}
