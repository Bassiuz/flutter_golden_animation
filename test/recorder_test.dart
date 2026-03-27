import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/recorder.dart';
import 'package:flutter_golden_animation/src/apng/chunks.dart';

void main() {
  group('AnimationRecorder', () {
    testWidgets('captures frames from an animating widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 500),
              builder: (context, value, child) {
                return Opacity(opacity: value, child: child);
              },
              child: const SizedBox(
                width: 50,
                height: 50,
                child: ColoredBox(color: Colors.red),
              ),
            ),
          ),
        ),
      );

      final recorder = AnimationRecorder(tester);

      await recorder.record(
        duration: const Duration(milliseconds: 500),
        frameRate: 10, // 10 fps = 100ms intervals = 5 frames
      );

      expect(recorder.frames, isNotEmpty);
      expect(recorder.frames.length, equals(5));

      // Each frame should be valid PNG bytes
      for (final frame in recorder.frames) {
        expect(frame.sublist(0, 8), equals(pngSignature));
      }
    });

    testWidgets('runs interaction callback before recording', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            child: TextButton(
              onPressed: () => tapped = true,
              child: const Text('Tap me'),
            ),
          ),
        ),
      );

      final recorder = AnimationRecorder(tester);

      await recorder.record(
        interaction: () async {
          await tester.tap(find.byType(TextButton));
        },
        duration: const Duration(milliseconds: 100),
        frameRate: 10,
      );

      expect(tapped, isTrue);
    });

    testWidgets('toApng returns valid APNG bytes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            child: const SizedBox(
              width: 10,
              height: 10,
              child: ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      );

      final recorder = AnimationRecorder(tester);

      await recorder.record(
        duration: const Duration(milliseconds: 200),
        frameRate: 10,
      );

      final apng = recorder.toApng();

      // Should be valid APNG (has acTL chunk)
      final chunks = parsePngChunks(apng);
      expect(chunks.map((c) => c.type), contains('acTL'));
    });
  });
}
