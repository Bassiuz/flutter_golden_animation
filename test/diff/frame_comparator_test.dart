import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/diff/frame_comparator.dart';
import '../helpers/test_png.dart';

void main() {
  group('FrameComparisonResult', () {
    test('identical frames produce 0% diff and passed=true', () {
      final frame = createTestPng(red: 128, green: 64, blue: 32);
      final result = compareFrames(frame, frame);

      expect(result.passed, isTrue);
      expect(result.diffPercent, equals(0.0));
    });

    test('different frames produce non-zero diff and passed=false', () {
      final frame1 = createTestPng(red: 255, green: 0, blue: 0);
      final frame2 = createTestPng(red: 0, green: 255, blue: 0);
      final result = compareFrames(frame1, frame2);

      expect(result.passed, isFalse);
      expect(result.diffPercent, greaterThan(0.0));
    });

    test('respects tolerance threshold', () {
      final frame1 = createTestPng(red: 255);
      final frame2 = createTestPng(red: 254); // very small diff
      final result = compareFrames(frame1, frame2, tolerance: 100.0);

      // With 100% tolerance, even different frames pass
      expect(result.passed, isTrue);
    });

    test('zero tolerance fails on any difference', () {
      final frame1 = createTestPng(red: 255);
      final frame2 = createTestPng(red: 254);
      final result = compareFrames(frame1, frame2, tolerance: 0.0);

      expect(result.passed, isFalse);
    });
  });
}
