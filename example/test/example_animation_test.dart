import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/flutter_golden_animation.dart';
import 'package:flutter_golden_animation_example/example_button.dart';

void main() {
  setupGoldenAnimationCompare();

  testWidgets('ExampleButton press animation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          child: const ExampleButton(),
        ),
      ),
    );

    final recorder = AnimationRecorder(tester);

    await recorder.record(
      interaction: () async {
        await tester.tap(find.byType(ExampleButton));
      },
      duration: const Duration(milliseconds: 300),
      frameRate: 10,
    );

    await recorder.compareWithGolden('goldens/example_button_press.apng');
  });
}
