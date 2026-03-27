# flutter_golden_animation

[![pub package](https://img.shields.io/pub/v/flutter_golden_animation.svg)](https://pub.dev/packages/flutter_golden_animation)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Animation golden testing for Flutter. Captures widget animation frames as lossless APNG golden files with pixel-perfect comparison, frame-level diff reporting, and an auto-generated HTML viewer.

APNG goldens render inline on GitHub, so reviewers can watch animations play directly in pull requests.

## Features

- Record widget animations frame-by-frame at any frame rate
- Lossless APNG golden files (full RGBA, no compression artifacts)
- Pixel-perfect comparison with configurable tolerance
- Detailed failure artifacts: expected/actual/diff APNGs + per-frame diffs + text report
- Auto-generated `viewer.html` for browsing animations locally in any browser
- Zero external dependencies
- Standard `--update-goldens` workflow

## Installation

Add as a dev dependency:

```yaml
dev_dependencies:
  flutter_golden_animation: ^0.1.0
```

## Quick Start

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

## How It Works

1. **Record** -- `AnimationRecorder` captures frames via `RepaintBoundary.toImage()` at the specified frame rate.
2. **Encode** -- Frames are encoded into a lossless APNG file (the golden).
3. **Compare** -- On subsequent test runs, each frame is compared pixel-by-pixel against the golden.
4. **Review** -- APNG goldens render inline on GitHub. A `viewer.html` is generated alongside goldens for local viewing.

## Updating Goldens

Use the standard Flutter workflow:

```
flutter test --update-goldens
```

This regenerates all golden APNG files and the `viewer.html` alongside them.

## API Reference

### `setupGoldenAnimationCompare({double tolerance = 0.0})`

Call once at the top of your test file. Installs the `ApngGoldenComparator` so `.apng` goldens are compared frame-by-frame.

- `tolerance` -- Maximum allowed pixel diff percentage per frame (default: `0.0`, pixel-perfect).

### `AnimationRecorder`

```dart
final recorder = AnimationRecorder(tester);
```

**`record({interaction, duration, frameRate})`**

Records animation frames. The optional `interaction` callback (e.g., a tap) fires before frame capture begins. `duration` controls how long to record, `frameRate` sets the capture rate in fps (default: 60).

**`compareWithGolden(String path)`**

Compares recorded frames against the golden APNG at `path`. When run with `--update-goldens`, writes the golden instead of comparing.

**`toApng()`**

Returns the recorded frames as APNG bytes without comparing. Useful for custom workflows.

**`frames`**

The captured frames as a list of PNG byte arrays.

### `ApngGoldenComparator`

For advanced use. Extends Flutter's `GoldenFileComparator` with APNG-aware comparison. Use `setupGoldenAnimationCompare()` for the standard setup, or instantiate directly for custom configuration:

```dart
goldenFileComparator = ApngGoldenComparator(
  testDir: Directory.current.uri,
  tolerance: 0.5, // allow 0.5% pixel diff per frame
);
```

## Failure Artifacts

When a comparison fails, detailed artifacts are written to a `failures/` directory:

```
failures/
  button_press/
    expected.apng      -- the golden animation
    actual.apng        -- what the test produced
    diff.apng          -- animated diff with changed pixels in red
    frame_012_diff.png -- per-frame diff for failing frames
    report.txt         -- summary with per-frame mismatch percentages
    viewer.html        -- open in browser to see all artifacts
```

## Viewing Goldens

APNG files don't play in Finder or most image viewers. To view your golden animations:

- **In browser** -- Open the auto-generated `viewer.html` in the goldens directory
- **On GitHub** -- APNG files render and animate inline in PRs and file views
- **In VS Code** -- Right-click `viewer.html` and choose "Open with Live Server" or "Open in Browser"

## License

MIT. See [LICENSE](LICENSE) for details.
