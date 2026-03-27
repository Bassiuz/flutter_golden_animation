import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/diff/report.dart';
import 'package:flutter_golden_animation/src/diff/frame_comparator.dart';

void main() {
  group('generateReport', () {
    test('reports all frames passing', () {
      final results = [
        FrameComparisonResult(passed: true, diffPercent: 0.0, diffPixels: 0, totalPixels: 100),
        FrameComparisonResult(passed: true, diffPercent: 0.0, diffPixels: 0, totalPixels: 100),
      ];

      final report = generateReport(results, 'button_press.apng');

      expect(report, contains('0 of 2 frames differ'));
    });

    test('reports failing frames with diff percentages', () {
      final results = [
        FrameComparisonResult(passed: true, diffPercent: 0.0, diffPixels: 0, totalPixels: 100),
        FrameComparisonResult(passed: false, diffPercent: 0.3, diffPixels: 3, totalPixels: 1000),
        FrameComparisonResult(passed: true, diffPercent: 0.0, diffPixels: 0, totalPixels: 100),
        FrameComparisonResult(passed: false, diffPercent: 1.2, diffPixels: 12, totalPixels: 1000),
      ];

      final report = generateReport(results, 'button_press.apng');

      expect(report, contains('2 of 4 frames differ'));
      expect(report, contains('Frame 1'));
      expect(report, contains('0.3%'));
      expect(report, contains('Frame 3'));
      expect(report, contains('1.2%'));
    });

    test('includes golden file name', () {
      final results = [
        FrameComparisonResult(passed: false, diffPercent: 5.0, diffPixels: 50, totalPixels: 1000),
      ];

      final report = generateReport(results, 'goldens/my_test.apng');

      expect(report, contains('goldens/my_test.apng'));
    });
  });
}
