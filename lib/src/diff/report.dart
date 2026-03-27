import 'frame_comparator.dart';

/// Generates a human-readable text report of frame comparison results.
String generateReport(List<FrameComparisonResult> results, String goldenName) {
  final failingFrames = <int>[];
  for (int i = 0; i < results.length; i++) {
    if (!results[i].passed) {
      failingFrames.add(i);
    }
  }

  final buffer = StringBuffer();
  buffer.writeln('Golden animation comparison: $goldenName');
  buffer.writeln('${failingFrames.length} of ${results.length} frames differ.');

  if (failingFrames.isNotEmpty) {
    buffer.writeln('');
    for (final i in failingFrames) {
      final r = results[i];
      buffer.writeln(
        'Frame $i: ${r.diffPercent.toStringAsFixed(1)}% diff '
        '(${r.diffPixels} of ${r.totalPixels} pixels)',
      );
    }
  }

  return buffer.toString();
}
