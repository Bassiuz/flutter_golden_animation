import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/diff/diff_image.dart';
import 'package:flutter_golden_animation/src/apng/chunks.dart';
import '../helpers/test_png.dart';

void main() {
  group('generateDiffImage', () {
    test('produces a valid PNG', () {
      final frame1 = createTestPng(red: 255, green: 0, blue: 0);
      final frame2 = createTestPng(red: 0, green: 255, blue: 0);

      final diffPng = generateDiffImage(frame1, frame2);

      // Should be a valid PNG
      expect(diffPng.sublist(0, 8), equals(pngSignature));
      final chunks = parsePngChunks(diffPng);
      expect(chunks.map((c) => c.type), containsAll(['IHDR', 'IDAT', 'IEND']));
    });

    test('identical frames produce a transparent diff', () {
      final frame = createTestPng(red: 128, green: 128, blue: 128);

      final diffPng = generateDiffImage(frame, frame);

      expect(diffPng, isNotNull);
    });

    test('different frames produce non-transparent diff', () {
      final frame1 = createTestPng(red: 255, green: 0, blue: 0);
      final frame2 = createTestPng(red: 0, green: 0, blue: 255);

      final diffPng = generateDiffImage(frame1, frame2);

      expect(diffPng.length, greaterThan(0));
    });
  });
}
