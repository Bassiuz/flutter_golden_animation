import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apng/decoder.dart';
import 'apng/encoder.dart';
import 'diff/diff_image.dart';
import 'diff/frame_comparator.dart';
import 'diff/report.dart';
import 'viewer.dart';

/// Custom [GoldenFileComparator] that handles APNG comparison and
/// generates failure artifacts (expected, actual, diff APNGs and a report).
class ApngGoldenComparator extends GoldenFileComparator {
  ApngGoldenComparator({
    required this.testDir,
    this.tolerance = 0.0,
  });

  /// The base directory used to resolve relative golden file URIs.
  final Uri testDir;

  /// Maximum allowed diff percentage per frame (0.0 = pixel-perfect).
  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final goldenFile = File.fromUri(_resolveUri(golden));

    if (!goldenFile.existsSync()) {
      throw FlutterError(
        'Golden file not found: ${goldenFile.path}\n'
        'Run with --update-goldens to create it.',
      );
    }

    final goldenBytes = goldenFile.readAsBytesSync();

    final testResult = decodeApng(imageBytes);
    final goldenResult = decodeApng(Uint8List.fromList(goldenBytes));

    // Check frame count
    if (testResult.frames.length != goldenResult.frames.length) {
      await _writeFailureArtifacts(
        golden: goldenBytes,
        test: imageBytes,
        goldenUri: golden,
        message: 'Frame count mismatch: expected ${goldenResult.frames.length}, '
            'got ${testResult.frames.length}',
      );
      throw FlutterError(
        'Animation golden test failed: ${goldenFile.path}\n'
        'Frame count mismatch: expected ${goldenResult.frames.length}, '
        'got ${testResult.frames.length}',
      );
    }

    // Compare each frame
    final results = <FrameComparisonResult>[];
    for (int i = 0; i < testResult.frames.length; i++) {
      results.add(compareFrames(
        goldenResult.frames[i],
        testResult.frames[i],
        tolerance: tolerance,
      ));
    }

    final hasFailures = results.any((r) => !r.passed);
    if (hasFailures) {
      final diffFrames = <Uint8List>[];
      for (int i = 0; i < testResult.frames.length; i++) {
        diffFrames.add(generateDiffImage(
          goldenResult.frames[i],
          testResult.frames[i],
        ));
      }

      await _writeFailureArtifacts(
        golden: goldenBytes,
        test: imageBytes,
        goldenUri: golden,
        diffFrames: diffFrames,
        results: results,
        frameDelayMs: goldenResult.frameDelayMs,
      );

      final report = generateReport(results, golden.pathSegments.last);
      throw FlutterError(
        'Animation golden test failed: ${goldenFile.path}\n$report',
      );
    }

    return true;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    final goldenFile = File.fromUri(_resolveUri(golden));
    await goldenFile.parent.create(recursive: true);
    await goldenFile.writeAsBytes(imageBytes, flush: true);
    await generateViewer(goldenFile.parent);
  }

  Uri _resolveUri(Uri golden) {
    return golden.isAbsolute ? golden : testDir.resolveUri(golden);
  }

  Future<void> _writeFailureArtifacts({
    required Uint8List golden,
    required Uint8List test,
    required Uri goldenUri,
    String? message,
    List<Uint8List>? diffFrames,
    List<FrameComparisonResult>? results,
    int? frameDelayMs,
  }) async {
    final goldenName = goldenUri.pathSegments.last.replaceAll('.apng', '');
    final failDir = Directory.fromUri(testDir.resolve('failures/$goldenName/'));
    await failDir.create(recursive: true);

    await File('${failDir.path}/expected.apng').writeAsBytes(golden);
    await File('${failDir.path}/actual.apng').writeAsBytes(test);

    if (diffFrames != null && diffFrames.isNotEmpty) {
      final diffApng = encodeApng(
        frames: diffFrames,
        frameDelayMs: frameDelayMs ?? 100,
      );
      await File('${failDir.path}/diff.apng').writeAsBytes(diffApng);

      if (results != null) {
        for (int i = 0; i < results.length; i++) {
          if (!results[i].passed) {
            await File(
              '${failDir.path}/frame_${i.toString().padLeft(3, '0')}_diff.png',
            ).writeAsBytes(diffFrames[i]);
          }
        }
      }
    }

    if (results != null) {
      final report = generateReport(results, goldenUri.pathSegments.last);
      await File('${failDir.path}/report.txt').writeAsString(report);
    } else if (message != null) {
      await File('${failDir.path}/report.txt').writeAsString(message);
    }

    await generateViewer(failDir);
  }
}
