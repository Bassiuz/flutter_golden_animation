# Flutter Golden Animation — Design Document

## Overview

**flutter_golden_animation** is a Flutter test package that enables animation golden testing. It captures widget animation frames, stores them as a single lossless APNG golden file, and provides frame-level diff reporting when tests fail.

Zero external dependencies — only the Flutter SDK.

## Developer API

```dart
import 'package:flutter_golden_animation/flutter_golden_animation.dart';

void main() {
  setupGoldenAnimationCompare(); // registers the custom GoldenFileComparator

  testWidgets('button press animation', (tester) async {
    await tester.pumpWidget(MaterialApp(home: MyButton()));

    final recorder = AnimationRecorder(tester);

    await recorder.record(
      interaction: () => tester.tap(find.byType(MyButton)),
      duration: Duration(milliseconds: 500),
      frameRate: 60,
    );

    await recorder.compareWithGolden('goldens/button_press.apng');
  });
}
```

### AnimationRecorder

Takes a `WidgetTester` and provides:

- **`record()`** — Pumps frames over the given duration at the specified frame rate, capturing each frame via `RepaintBoundary.toImage()`. The `interaction` callback fires before the frame pumping begins.
- **`compareWithGolden(path)`** — Triggers comparison against the golden APNG using the custom comparator.

### setupGoldenAnimationCompare()

A one-liner that sets `goldenFileComparator` to the package's custom `ApngGoldenComparator`. Supports an optional `tolerance` parameter (defaults to 0.0 — pixel-perfect).

## APNG Encoding & Decoding

Custom minimal APNG encoder and decoder — no dependency on the `image` package.

### Encoder

Takes a `List<Uint8List>` (individual PNG file bytes) and a frame duration, produces a single APNG file:

1. Uses the first PNG's IHDR chunk as the APNG's IHDR
2. Writes an `acTL` (animation control) chunk with frame count and loop count
3. For each frame: writes `fcTL` (frame control) chunk with dimensions, offsets, and timing, followed by frame data as `fdAT` chunks (frames 2+) or standard `IDAT` (frame 1)
4. Writes the `IEND` chunk

The first frame doubles as the static fallback image — any PNG viewer that doesn't support APNG shows frame 1.

### Decoder

Takes APNG bytes and splits them back into individual PNG frames:

1. Reads the `acTL` chunk to get the frame count
2. Walks through `fcTL`/`fdAT`/`IDAT` chunks, reconstructing each frame as a standalone PNG
3. Returns a `List<Uint8List>` of PNG bytes plus timing metadata

### Determinism

The encoder produces byte-identical output for the same input — no timestamps, no random IDs, no compression-level variance. Achieved by passing through original PNG chunk data without re-encoding.

## Custom Comparator & Failure Reporting

### ApngGoldenComparator

Implements Flutter's `GoldenFileComparator` with two methods:

**`compare(Uint8List test, Uri golden)`**

1. Decode the test APNG into frames
2. Decode the golden APNG into frames
3. If frame counts differ — fail immediately with a clear message
4. Compare each frame pair pixel-by-pixel, tracking diff percentage per frame
5. If any frame exceeds the tolerance — fail and generate failure artifacts

**`update(Uri golden, Uint8List test)`**

Called when running `flutter test --update-goldens`. Writes the test APNG bytes to the golden file path.

### Failure Artifacts

When comparison fails, writes to a `failures/` directory:

```
failures/
  button_press/
    expected.apng      — the golden animation
    actual.apng        — what the test produced
    diff.apng          — animated overlay highlighting pixel differences
    frame_012_diff.png — individual diff PNG for each failing frame
    frame_017_diff.png
    report.txt         — summary with per-frame diff percentages
```

The `diff.apng` uses a red highlight overlay on changed pixels.

## Package Structure

```
flutter_golden_animation/
  lib/
    flutter_golden_animation.dart          — public barrel export
    src/
      recorder.dart                        — AnimationRecorder class
      comparator.dart                      — ApngGoldenComparator class
      apng/
        encoder.dart                       — APNG encoder
        decoder.dart                       — APNG decoder
        chunks.dart                        — PNG chunk reading/writing utilities
      diff/
        frame_comparator.dart              — pixel-level frame comparison
        diff_image.dart                    — generates red-overlay diff PNGs
        report.dart                        — text report generation
  test/
    recorder_test.dart
    comparator_test.dart
    apng/
      encoder_test.dart
      decoder_test.dart
      round_trip_test.dart                 — encode then decode, verify identical
    diff/
      frame_comparator_test.dart
  example/
    test/
      example_animation_test.dart          — working example developers can copy
  pubspec.yaml
  README.md
  LICENSE
```

## Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
```

Zero external dependencies.

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Golden format | Single APNG file | Reduces clutter in PRs, GitHub renders inline |
| Comparison default | Pixel-perfect (0.0 tolerance) | Matches Flutter convention, opt-in tolerance |
| API style | Composable (inside `testWidgets`) | Familiar to Flutter devs, flexible |
| Golden updates | `--update-goldens` flag | Standard Flutter workflow, zero new concepts |
| APNG implementation | Custom encoder/decoder | Avoids heavy `image` package dependency, full control over determinism |
| Failure output | Per-frame diffs + animated diff APNG | Quick visual review + detailed debugging |
