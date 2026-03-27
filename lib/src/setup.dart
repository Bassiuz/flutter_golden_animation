import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'comparator.dart';

/// Registers the [ApngGoldenComparator] as the golden file comparator.
///
/// Call this at the top of your test's `main()` function:
///
/// ```dart
/// void main() {
///   setupGoldenAnimationCompare();
///   // ... your tests
/// }
/// ```
///
/// [tolerance] is the maximum allowed diff percentage per frame
/// (0.0 = pixel-perfect, which is the default).
void setupGoldenAnimationCompare({double tolerance = 0.0}) {
  final testDir = Directory.current.uri;
  goldenFileComparator = ApngGoldenComparator(
    testDir: testDir,
    tolerance: tolerance,
  );
}
