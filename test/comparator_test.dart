import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/comparator.dart';
import 'package:flutter_golden_animation/src/apng/encoder.dart';
import 'helpers/test_png.dart';

void main() {
  late Directory tempDir;
  late ApngGoldenComparator comparator;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('apng_golden_test_');
    comparator = ApngGoldenComparator(
      testDir: tempDir.uri,
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('ApngGoldenComparator', () {
    test('compare passes for identical APNGs', () async {
      final frames = [createTestPng(red: 255), createTestPng(green: 255)];
      final apng = encodeApng(frames: frames, frameDelayMs: 100);

      final goldenFile = File('${tempDir.path}/test.apng');
      goldenFile.writeAsBytesSync(apng);

      final result = await comparator.compare(apng, goldenFile.uri);
      expect(result, isTrue);
    });

    test('compare fails for different APNGs', () async {
      final golden = encodeApng(
        frames: [createTestPng(red: 255)],
        frameDelayMs: 100,
      );
      final test = encodeApng(
        frames: [createTestPng(green: 255)],
        frameDelayMs: 100,
      );

      final goldenFile = File('${tempDir.path}/test.apng');
      goldenFile.writeAsBytesSync(golden);

      expect(
        () => comparator.compare(test, goldenFile.uri),
        throwsA(isA<FlutterError>()),
      );
    });

    test('compare fails when frame counts differ', () async {
      final golden = encodeApng(
        frames: [createTestPng(), createTestPng()],
        frameDelayMs: 100,
      );
      final test = encodeApng(
        frames: [createTestPng()],
        frameDelayMs: 100,
      );

      final goldenFile = File('${tempDir.path}/test.apng');
      goldenFile.writeAsBytesSync(golden);

      expect(
        () => comparator.compare(test, goldenFile.uri),
        throwsA(isA<FlutterError>()),
      );
    });

    test('update writes APNG to golden path', () async {
      final apng = encodeApng(
        frames: [createTestPng()],
        frameDelayMs: 100,
      );
      final goldenUri = Uri.file('${tempDir.path}/new_golden.apng');

      await comparator.update(goldenUri, apng);

      final written = File.fromUri(goldenUri);
      expect(written.existsSync(), isTrue);
      expect(written.readAsBytesSync(), equals(apng));
    });

    test('compare generates failure artifacts', () async {
      final golden = encodeApng(
        frames: [createTestPng(red: 255)],
        frameDelayMs: 100,
      );
      final test = encodeApng(
        frames: [createTestPng(green: 255)],
        frameDelayMs: 100,
      );

      final goldenFile = File('${tempDir.path}/button.apng');
      goldenFile.writeAsBytesSync(golden);

      try {
        await comparator.compare(test, goldenFile.uri);
      } on FlutterError {
        // Expected
      }

      final failDir = Directory('${tempDir.path}/failures/button');
      expect(failDir.existsSync(), isTrue);
      expect(File('${failDir.path}/expected.apng').existsSync(), isTrue);
      expect(File('${failDir.path}/actual.apng').existsSync(), isTrue);
      expect(File('${failDir.path}/diff.apng').existsSync(), isTrue);
      expect(File('${failDir.path}/report.txt').existsSync(), isTrue);
    });
  });
}
