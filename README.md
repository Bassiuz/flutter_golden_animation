# flutter_golden_animation

Animation golden testing for Flutter. Captures animation frames as APNG goldens with frame-level diff reporting. Zero external dependencies.

## Installation

Add the package as a dev dependency in your `pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_golden_animation:
    git:
      url: https://github.com/bassiuz/flutter_golden_animation.git
```

Then run `fvm flutter pub get`.

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/flutter_golden_animation.dart';

void main() {
  setupGoldenAnimationCompare();

  testWidgets('button press animation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          child: const MyButton(),
        ),
      ),
    );

    final recorder = AnimationRecorder(tester);

    await recorder.record(
      interaction: () => tester.tap(find.byType(MyButton)),
      duration: Duration(milliseconds: 300),
      frameRate: 10,
    );

    await recorder.compareWithGolden('goldens/button_press.apng');
  });
}
```

## How it works

1. `AnimationRecorder` captures frames via `RepaintBoundary.toImage()` at the specified frame rate.
2. Frames are encoded into a lossless APNG file (the golden).
3. APNG goldens render inline on GitHub -- reviewers can see the animation play directly in PRs.
4. On test failure: generates expected/actual/diff APNGs, per-frame diff PNGs, and a text report.

## Updating goldens

Use the standard Flutter workflow:

```
fvm flutter test --update-goldens
```

## API reference

### `setupGoldenAnimationCompare({double tolerance})`

Call once at the top of your test file (or in `setUpAll`). Installs the `ApngGoldenComparator` so that `.apng` golden files are compared frame-by-frame. The optional `tolerance` parameter controls how much pixel difference is allowed before a frame is marked as failed (default: 0.0).

### `AnimationRecorder(tester)`

Create an instance with your `WidgetTester`. Key methods:

- `record({required VoidCallback interaction, required Duration duration, required int frameRate})` -- Triggers the interaction, then pumps frames at the given rate for the specified duration.
- `compareWithGolden(String path)` -- Compares the recorded frames against the golden APNG at `path`. Creates the golden file when run with `--update-goldens`.

### `ApngGoldenComparator`

For advanced use. Lets you configure a custom tolerance or test directory directly, rather than going through `setupGoldenAnimationCompare`.

## Failure artifacts

When a golden comparison fails, the package writes detailed artifacts to a `failures/` directory:

```
failures/
  button_press/
    expected.apng
    actual.apng
    diff.apng
    frame_012_diff.png
    report.txt
```

- `expected.apng` / `actual.apng` -- The golden and the test run, viewable in any browser.
- `diff.apng` -- Animated diff highlighting changed pixels.
- `frame_NNN_diff.png` -- Per-frame diff images for frames that exceeded the tolerance.
- `report.txt` -- Human-readable summary with per-frame mismatch percentages.
