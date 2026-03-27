// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/flutter_golden_animation.dart';

void main() {
  // Register the APNG golden comparator
  setupGoldenAnimationCompare();

  testWidgets('my widget animation', (tester) async {
    // 1. Pump a widget wrapped in RepaintBoundary
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          child: ElevatedButton(
            onPressed: () {},
            child: const Text('Press me'),
          ),
        ),
      ),
    );

    // 2. Create a recorder
    final recorder = AnimationRecorder(tester);

    // 3. Record the animation (interaction fires first, then frames are captured)
    await recorder.record(
      interaction: () => tester.tap(find.byType(ElevatedButton)),
      duration: const Duration(milliseconds: 300),
      frameRate: 10, // 10 fps = one frame every 100ms
    );

    // 4. Compare against the golden APNG
    // First run: use `flutter test --update-goldens` to generate it
    await recorder.compareWithGolden('goldens/my_widget_animation.apng');
  });
}
