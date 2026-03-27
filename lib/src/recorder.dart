import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apng/encoder.dart';

/// Records animation frames from a widget test and encodes them as APNG.
///
/// Wrap your widget in a [RepaintBoundary], create an [AnimationRecorder],
/// call [record] to capture frames, then [compareWithGolden] to compare
/// against a golden APNG file.
///
/// ```dart
/// final recorder = AnimationRecorder(tester);
/// await recorder.record(
///   interaction: () => tester.tap(find.byType(MyButton)),
///   duration: Duration(milliseconds: 300),
///   frameRate: 10,
/// );
/// await recorder.compareWithGolden('goldens/my_animation.apng');
/// ```
class AnimationRecorder {
  /// Creates a recorder that uses the given [WidgetTester] to pump frames
  /// and capture images.
  AnimationRecorder(this._tester);

  final WidgetTester _tester;
  final List<Uint8List> _frames = [];
  int _frameDelayMs = 16;

  /// The captured frames as PNG byte arrays.
  List<Uint8List> get frames => List.unmodifiable(_frames);

  /// Records animation frames.
  ///
  /// [interaction] is called before frame recording starts.
  /// [duration] is the total time to record.
  /// [frameRate] is frames per second (default 60).
  Future<void> record({
    Future<void> Function()? interaction,
    required Duration duration,
    int frameRate = 60,
  }) async {
    _frames.clear();
    _frameDelayMs = (1000 / frameRate).round();
    final interval = Duration(milliseconds: _frameDelayMs);
    final totalFrames = (duration.inMilliseconds / _frameDelayMs).floor();

    if (interaction != null) {
      await interaction();
    }

    for (int i = 0; i < totalFrames; i++) {
      await _tester.pump(interval);
      final pngBytes = await _captureFrame();
      _frames.add(pngBytes);
    }
  }

  /// Encodes all captured frames into an APNG.
  Uint8List toApng() {
    if (_frames.isEmpty) {
      throw StateError('No frames recorded. Call record() first.');
    }
    return encodeApng(frames: _frames, frameDelayMs: _frameDelayMs);
  }

  /// Compares captured frames against a golden APNG file.
  ///
  /// Uses [WidgetTester.runAsync] internally for file I/O,
  /// so callers don't need to wrap this call themselves.
  Future<void> compareWithGolden(String goldenPath) async {
    final apngBytes = toApng();
    final uri = Uri.parse(goldenPath);

    await _tester.runAsync(() async {
      if (autoUpdateGoldenFiles) {
        await goldenFileComparator.update(uri, apngBytes);
      } else {
        final bool passed = await goldenFileComparator.compare(apngBytes, uri);
        if (!passed) {
          throw TestFailure('Animation golden test failed for $goldenPath');
        }
      }
    });
  }

  Future<Uint8List> _captureFrame() async {
    final element = _tester.binding.rootElement!;
    final renderObject = _findRepaintBoundary(element);

    if (renderObject == null) {
      throw StateError(
        'No RepaintBoundary found. Wrap your widget in a RepaintBoundary.',
      );
    }

    final image = await _tester.runAsync(() async {
      return renderObject.toImage(pixelRatio: 1.0);
    });

    final byteData = await _tester.runAsync(() async {
      return image!.toByteData(format: ui.ImageByteFormat.png);
    });

    image!.dispose();

    if (byteData == null) {
      throw StateError('Failed to capture frame as PNG');
    }

    return byteData.buffer.asUint8List();
  }

  RenderRepaintBoundary? _findRepaintBoundary(Element element) {
    RenderRepaintBoundary? boundary;

    void visitor(Element el) {
      if (boundary != null) return;
      final renderObject = el.renderObject;
      if (renderObject is RenderRepaintBoundary) {
        boundary = renderObject;
        return;
      }
      el.visitChildren(visitor);
    }

    visitor(element);
    return boundary;
  }
}
