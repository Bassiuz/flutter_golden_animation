## 0.1.1
- Update pubspec description.

## 0.1.0

- Initial release.
- `AnimationRecorder` for capturing widget animation frames in tests.
- `ApngGoldenComparator` for frame-by-frame APNG golden comparison.
- `setupGoldenAnimationCompare()` for quick setup.
- Custom APNG encoder/decoder with zero external dependencies.
- Pixel-perfect comparison with configurable tolerance.
- Failure artifacts: expected/actual/diff APNGs, per-frame diff PNGs, text report.
- Auto-generated HTML viewer for browsing golden animations locally.
- Full support for `--update-goldens` workflow.
