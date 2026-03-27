# Flutter Golden Animation — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Flutter test package that captures animation frames, stores them as APNG goldens, and provides frame-level diff reporting on failures.

**Architecture:** Composable API inside `testWidgets` — `AnimationRecorder` captures frames via `RepaintBoundary.toImage()`, a custom `ApngGoldenComparator` implements Flutter's `GoldenFileComparator` for APNG comparison, and a minimal custom APNG encoder/decoder avoids external dependencies.

**Tech Stack:** Flutter SDK only (flutter, flutter_test). No external dependencies.

---

### Task 1: Project Setup

**Files:**
- Create: `pubspec.yaml`
- Create: `lib/flutter_golden_animation.dart`
- Create: `lib/src/.gitkeep` (placeholder)
- Create: `analysis_options.yaml`

**Step 1: Create pubspec.yaml**

```yaml
name: flutter_golden_animation
description: Animation golden testing for Flutter — captures frames as APNG goldens with frame-level diff reporting.
version: 0.0.1
homepage: https://github.com/bassiuz/flutter_golden_animation

environment:
  sdk: ^3.7.1
  flutter: ">=3.29.0"

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
```

**Step 2: Create analysis_options.yaml**

```yaml
include: package:flutter/analysis_options_user.yaml
```

**Step 3: Create barrel export**

Create `lib/flutter_golden_animation.dart`:

```dart
library flutter_golden_animation;
```

**Step 4: Run flutter pub get**

Run: `flutter pub get`
Expected: Dependencies resolve successfully.

**Step 5: Run flutter analyze**

Run: `flutter analyze`
Expected: No issues found.

**Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/flutter_golden_animation.dart analysis_options.yaml
git commit -m "chore: initialize flutter_golden_animation package"
```

---

### Task 2: PNG Chunk Utilities

PNG and APNG files are built from chunks. This task creates the low-level chunk reading/writing utilities that the encoder and decoder depend on.

**Files:**
- Create: `lib/src/apng/chunks.dart`
- Create: `test/apng/chunks_test.dart`

**Step 1: Write the failing tests**

Create `test/apng/chunks_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/apng/chunks.dart';

void main() {
  group('PngChunk', () {
    test('roundtrips type and data through toBytes/fromBytes', () {
      final chunk = PngChunk('tEXt', Uint8List.fromList([0x48, 0x69]));
      final bytes = chunk.toBytes();
      final parsed = PngChunk.fromBytes(bytes);

      expect(parsed.type, equals('tEXt'));
      expect(parsed.data, equals(Uint8List.fromList([0x48, 0x69])));
    });

    test('calculates correct CRC', () {
      final chunk = PngChunk('tEXt', Uint8List.fromList([0x48, 0x69]));
      final bytes = chunk.toBytes();
      // CRC covers type + data
      // Re-parsing should not throw (CRC validation)
      expect(() => PngChunk.fromBytes(bytes, validateCrc: true), returnsNormally);
    });

    test('fromBytes rejects invalid CRC when validation enabled', () {
      final chunk = PngChunk('tEXt', Uint8List.fromList([0x48, 0x69]));
      final bytes = chunk.toBytes();
      // Corrupt the last byte (part of CRC)
      bytes[bytes.length - 1] ^= 0xFF;
      expect(
        () => PngChunk.fromBytes(bytes, validateCrc: true),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('parsePngChunks', () {
    test('parses a minimal valid PNG into chunks', () {
      // Build a minimal valid PNG: signature + IHDR + IEND
      final builder = BytesBuilder();
      // PNG signature
      builder.add(pngSignature);
      // IHDR chunk (13 bytes of data: width, height, bit depth, color type, etc.)
      final ihdrData = Uint8List(13);
      final ihdrView = ByteData.sublistView(ihdrData);
      ihdrView.setUint32(0, 1); // width = 1
      ihdrView.setUint32(4, 1); // height = 1
      ihdrData[8] = 8;  // bit depth
      ihdrData[9] = 6;  // color type (RGBA)
      ihdrData[10] = 0; // compression
      ihdrData[11] = 0; // filter
      ihdrData[12] = 0; // interlace
      builder.add(PngChunk('IHDR', ihdrData).toBytes());
      // IEND chunk (0 bytes of data)
      builder.add(PngChunk('IEND', Uint8List(0)).toBytes());

      final png = Uint8List.fromList(builder.toBytes());
      final chunks = parsePngChunks(png);

      expect(chunks.length, equals(2));
      expect(chunks[0].type, equals('IHDR'));
      expect(chunks[1].type, equals('IEND'));
    });

    test('throws on invalid PNG signature', () {
      expect(
        () => parsePngChunks(Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0])),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('buildPng', () {
    test('produces valid PNG bytes from chunks', () {
      final ihdrData = Uint8List(13);
      final ihdrView = ByteData.sublistView(ihdrData);
      ihdrView.setUint32(0, 1);
      ihdrView.setUint32(4, 1);
      ihdrData[8] = 8;
      ihdrData[9] = 6;
      final chunks = [
        PngChunk('IHDR', ihdrData),
        PngChunk('IEND', Uint8List(0)),
      ];

      final pngBytes = buildPng(chunks);

      // Should start with PNG signature
      expect(pngBytes.sublist(0, 8), equals(pngSignature));
      // Should be re-parseable
      final reparsed = parsePngChunks(pngBytes);
      expect(reparsed.length, equals(2));
    });
  });
}
```

**Step 2: Run tests to verify they fail**

Run: `flutter test test/apng/chunks_test.dart`
Expected: FAIL — cannot find `chunks.dart` module.

**Step 3: Implement chunks.dart**

Create `lib/src/apng/chunks.dart`:

```dart
import 'dart:typed_data';

/// Standard PNG file signature (8 bytes).
const List<int> pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

/// A single PNG chunk with a 4-character type and data payload.
class PngChunk {
  PngChunk(this.type, this.data) : assert(type.length == 4);

  /// Parses a single chunk from raw bytes (length + type + data + CRC).
  factory PngChunk.fromBytes(Uint8List bytes, {bool validateCrc = false}) {
    if (bytes.length < 12) {
      throw FormatException('Chunk too short: ${bytes.length} bytes');
    }
    final view = ByteData.sublistView(bytes);
    final length = view.getUint32(0);
    if (bytes.length < 12 + length) {
      throw FormatException('Chunk data truncated');
    }
    final type = String.fromCharCodes(bytes.sublist(4, 8));
    final data = Uint8List.sublistView(bytes, 8, 8 + length);

    if (validateCrc) {
      final expectedCrc = view.getUint32(8 + length);
      final actualCrc = _crc32(bytes.sublist(4, 8 + length));
      if (expectedCrc != actualCrc) {
        throw FormatException(
          'CRC mismatch for chunk $type: '
          'expected 0x${expectedCrc.toRadixString(16)}, '
          'got 0x${actualCrc.toRadixString(16)}',
        );
      }
    }

    return PngChunk(type, data);
  }

  final String type;
  final Uint8List data;

  /// Serializes this chunk to bytes: [length(4)] [type(4)] [data(N)] [crc(4)].
  Uint8List toBytes() {
    final length = data.length;
    final bytes = Uint8List(12 + length);
    final view = ByteData.sublistView(bytes);

    // Length
    view.setUint32(0, length);
    // Type
    for (int i = 0; i < 4; i++) {
      bytes[4 + i] = type.codeUnitAt(i);
    }
    // Data
    bytes.setRange(8, 8 + length, data);
    // CRC over type + data
    final crc = _crc32(bytes.sublist(4, 8 + length));
    view.setUint32(8 + length, crc);

    return bytes;
  }
}

/// Parses all chunks from a PNG/APNG file.
///
/// Validates the 8-byte PNG signature, then reads chunks sequentially.
List<PngChunk> parsePngChunks(Uint8List pngBytes) {
  if (pngBytes.length < 8) {
    throw FormatException('File too short to be a PNG');
  }
  for (int i = 0; i < 8; i++) {
    if (pngBytes[i] != pngSignature[i]) {
      throw FormatException('Invalid PNG signature');
    }
  }

  final chunks = <PngChunk>[];
  int offset = 8; // skip signature

  while (offset < pngBytes.length) {
    final view = ByteData.sublistView(pngBytes, offset);
    final length = view.getUint32(0);
    final chunkSize = 12 + length; // length(4) + type(4) + data(length) + crc(4)

    if (offset + chunkSize > pngBytes.length) {
      throw FormatException('Chunk extends beyond file end at offset $offset');
    }

    final chunkBytes = Uint8List.sublistView(pngBytes, offset, offset + chunkSize);
    chunks.add(PngChunk.fromBytes(chunkBytes));
    offset += chunkSize;
  }

  return chunks;
}

/// Builds a complete PNG file from a list of chunks.
Uint8List buildPng(List<PngChunk> chunks) {
  final builder = BytesBuilder();
  builder.add(pngSignature);
  for (final chunk in chunks) {
    builder.add(chunk.toBytes());
  }
  return Uint8List.fromList(builder.toBytes());
}

// --- CRC-32 implementation (PNG uses CRC-32/ISO-3309) ---

final Uint32List _crc32Table = _buildCrc32Table();

Uint32List _buildCrc32Table() {
  final table = Uint32List(256);
  for (int n = 0; n < 256; n++) {
    int c = n;
    for (int k = 0; k < 8; k++) {
      if (c & 1 != 0) {
        c = 0xEDB88320 ^ (c >> 1);
      } else {
        c = c >> 1;
      }
    }
    table[n] = c;
  }
  return table;
}

int _crc32(List<int> bytes) {
  int crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = _crc32Table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFF;
}
```

**Step 4: Run tests to verify they pass**

Run: `flutter test test/apng/chunks_test.dart`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/src/apng/chunks.dart test/apng/chunks_test.dart
git commit -m "feat: add PNG chunk reading/writing utilities"
```

---

### Task 3: APNG Encoder

**Files:**
- Create: `lib/src/apng/encoder.dart`
- Create: `test/apng/encoder_test.dart`

**Step 1: Write the failing tests**

Create `test/apng/encoder_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/apng/encoder.dart';
import 'package:flutter_golden_animation/src/apng/chunks.dart';

/// Creates a minimal valid 1x1 red RGBA PNG for testing.
Uint8List createTestPng({int red = 255, int green = 0, int blue = 0, int alpha = 255}) {
  // We build a minimal PNG by hand: IHDR + IDAT + IEND
  final builder = BytesBuilder();
  builder.add(pngSignature);

  // IHDR: 1x1, 8-bit RGBA
  final ihdrData = Uint8List(13);
  final ihdrView = ByteData.sublistView(ihdrData);
  ihdrView.setUint32(0, 1); // width
  ihdrView.setUint32(4, 1); // height
  ihdrData[8] = 8;  // bit depth
  ihdrData[9] = 6;  // color type RGBA
  ihdrData[10] = 0; // compression
  ihdrData[11] = 0; // filter
  ihdrData[12] = 0; // interlace
  builder.add(PngChunk('IHDR', ihdrData).toBytes());

  // IDAT: zlib-compressed row (filter byte 0 + RGBA pixel)
  // Raw data: [0x00, red, green, blue, alpha] (filter=none, then pixel)
  // We need to zlib compress this
  final rawRow = Uint8List.fromList([0, red, green, blue, alpha]);
  final compressed = _zlibCompress(rawRow);
  builder.add(PngChunk('IDAT', compressed).toBytes());

  // IEND
  builder.add(PngChunk('IEND', Uint8List(0)).toBytes());

  return Uint8List.fromList(builder.toBytes());
}

/// Minimal zlib compression using dart:io.
Uint8List _zlibCompress(Uint8List data) {
  // Use dart:io ZLibCodec
  final codec = ZLibCodec(level: 0); // no compression for determinism
  return Uint8List.fromList(codec.encode(data));
}

void main() {
  group('ApngEncoder', () {
    test('encodes a single frame as valid APNG', () {
      final frame = createTestPng();
      final apng = encodeApng(
        frames: [frame],
        frameDelayMs: 100,
      );

      // Should start with PNG signature
      expect(apng.sublist(0, 8), equals(pngSignature));

      // Should contain acTL chunk
      final chunks = parsePngChunks(apng);
      final chunkTypes = chunks.map((c) => c.type).toList();
      expect(chunkTypes, contains('acTL'));
      expect(chunkTypes, contains('IHDR'));
      expect(chunkTypes, contains('IEND'));
    });

    test('encodes multiple frames with correct frame count', () {
      final frame1 = createTestPng(red: 255);
      final frame2 = createTestPng(red: 0, green: 255);
      final frame3 = createTestPng(blue: 255);

      final apng = encodeApng(
        frames: [frame1, frame2, frame3],
        frameDelayMs: 100,
      );

      final chunks = parsePngChunks(apng);

      // acTL should report 3 frames
      final acTL = chunks.firstWhere((c) => c.type == 'acTL');
      final acTLView = ByteData.sublistView(acTL.data);
      expect(acTLView.getUint32(0), equals(3)); // num_frames

      // Should have 3 fcTL chunks (one per frame)
      final fcTLCount = chunks.where((c) => c.type == 'fcTL').length;
      expect(fcTLCount, equals(3));
    });

    test('produces deterministic output', () {
      final frame = createTestPng();
      final apng1 = encodeApng(frames: [frame], frameDelayMs: 100);
      final apng2 = encodeApng(frames: [frame], frameDelayMs: 100);

      expect(apng1, equals(apng2));
    });

    test('throws on empty frame list', () {
      expect(
        () => encodeApng(frames: [], frameDelayMs: 100),
        throwsArgumentError,
      );
    });
  });
}
```

**Step 2: Run tests to verify they fail**

Run: `flutter test test/apng/encoder_test.dart`
Expected: FAIL — cannot find `encoder.dart`.

**Step 3: Implement encoder.dart**

Create `lib/src/apng/encoder.dart`:

```dart
import 'dart:typed_data';

import 'chunks.dart';

/// Encodes a list of PNG frame byte arrays into a single APNG file.
///
/// All frames must have the same dimensions. [frameDelayMs] sets the
/// delay between frames in milliseconds. The animation loops forever.
///
/// The output is deterministic: identical inputs always produce identical bytes.
Uint8List encodeApng({
  required List<Uint8List> frames,
  required int frameDelayMs,
  int loopCount = 0, // 0 = infinite loop
}) {
  if (frames.isEmpty) {
    throw ArgumentError('frames must not be empty');
  }

  // Parse the first frame to get IHDR and IDAT
  final firstFrameChunks = parsePngChunks(frames[0]);
  final ihdr = firstFrameChunks.firstWhere((c) => c.type == 'IHDR');

  // Read dimensions from IHDR
  final ihdrView = ByteData.sublistView(ihdr.data);
  final width = ihdrView.getUint32(0);
  final height = ihdrView.getUint32(4);

  final outputChunks = <PngChunk>[];

  // 1. IHDR (from first frame)
  outputChunks.add(ihdr);

  // 2. acTL (animation control)
  final acTLData = Uint8List(8);
  final acTLView = ByteData.sublistView(acTLData);
  acTLView.setUint32(0, frames.length); // num_frames
  acTLView.setUint32(4, loopCount);     // num_plays (0 = infinite)
  outputChunks.add(PngChunk('acTL', acTLData));

  int sequenceNumber = 0;

  for (int i = 0; i < frames.length; i++) {
    final frameChunks = parsePngChunks(frames[i]);

    // 3. fcTL (frame control) for each frame
    final fcTLData = Uint8List(26);
    final fcTLView = ByteData.sublistView(fcTLData);
    fcTLView.setUint32(0, sequenceNumber++); // sequence_number
    fcTLView.setUint32(4, width);            // width
    fcTLView.setUint32(8, height);           // height
    fcTLView.setUint32(12, 0);              // x_offset
    fcTLView.setUint32(16, 0);              // y_offset
    fcTLView.setUint16(20, frameDelayMs);   // delay_num (ms)
    fcTLView.setUint16(22, 1000);           // delay_den (per second)
    fcTLData[24] = 0; // dispose_op: APNG_DISPOSE_OP_NONE
    fcTLData[25] = 0; // blend_op: APNG_BLEND_OP_SOURCE
    outputChunks.add(PngChunk('fcTL', fcTLData));

    // 4. Frame image data
    // First frame uses IDAT (for backwards compat with PNG viewers)
    // Subsequent frames use fdAT
    final idatChunks = frameChunks.where((c) => c.type == 'IDAT');
    for (final idat in idatChunks) {
      if (i == 0) {
        outputChunks.add(idat);
      } else {
        // fdAT = sequence_number(4) + IDAT data
        final fdATData = Uint8List(4 + idat.data.length);
        ByteData.sublistView(fdATData).setUint32(0, sequenceNumber++);
        fdATData.setRange(4, fdATData.length, idat.data);
        outputChunks.add(PngChunk('fdAT', fdATData));
      }
    }
  }

  // 5. IEND
  outputChunks.add(PngChunk('IEND', Uint8List(0)));

  return buildPng(outputChunks);
}
```

**Step 4: Run tests to verify they pass**

Run: `flutter test test/apng/encoder_test.dart`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/src/apng/encoder.dart test/apng/encoder_test.dart
git commit -m "feat: add APNG encoder"
```

---

### Task 4: APNG Decoder

**Files:**
- Create: `lib/src/apng/decoder.dart`
- Create: `test/apng/decoder_test.dart`

**Step 1: Write the failing tests**

Create `test/apng/decoder_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/apng/decoder.dart';
import 'package:flutter_golden_animation/src/apng/encoder.dart';
import 'package:flutter_golden_animation/src/apng/chunks.dart';

// Re-use the test PNG helper from encoder_test.dart — we'll extract it
// to a shared test helper in a later step. For now, duplicate it.

Uint8List createTestPng({int red = 255, int green = 0, int blue = 0, int alpha = 255}) {
  import 'dart:io';
  final builder = BytesBuilder();
  builder.add(pngSignature);

  final ihdrData = Uint8List(13);
  final ihdrView = ByteData.sublistView(ihdrData);
  ihdrView.setUint32(0, 1);
  ihdrView.setUint32(4, 1);
  ihdrData[8] = 8;
  ihdrData[9] = 6;
  builder.add(PngChunk('IHDR', ihdrData).toBytes());

  final rawRow = Uint8List.fromList([0, red, green, blue, alpha]);
  final compressed = ZLibCodec(level: 0).encode(rawRow);
  builder.add(PngChunk('IDAT', Uint8List.fromList(compressed)).toBytes());
  builder.add(PngChunk('IEND', Uint8List(0)).toBytes());

  return Uint8List.fromList(builder.toBytes());
}

void main() {
  group('ApngDecoder', () {
    test('decodes single-frame APNG', () {
      final frame = createTestPng();
      final apng = encodeApng(frames: [frame], frameDelayMs: 100);

      final result = decodeApng(apng);

      expect(result.frames.length, equals(1));
      expect(result.frameDelayMs, equals(100));
    });

    test('decodes multi-frame APNG with correct frame count', () {
      final frames = [
        createTestPng(red: 255),
        createTestPng(green: 255),
        createTestPng(blue: 255),
      ];
      final apng = encodeApng(frames: frames, frameDelayMs: 50);

      final result = decodeApng(apng);

      expect(result.frames.length, equals(3));
      expect(result.frameDelayMs, equals(50));
    });

    test('decoded frames are valid PNGs', () {
      final original = createTestPng(red: 128, green: 64, blue: 32);
      final apng = encodeApng(frames: [original], frameDelayMs: 100);

      final result = decodeApng(apng);
      final decodedFrame = result.frames[0];

      // Should start with PNG signature
      expect(decodedFrame.sublist(0, 8), equals(pngSignature));
      // Should be parseable
      final chunks = parsePngChunks(decodedFrame);
      expect(chunks.map((c) => c.type), containsAll(['IHDR', 'IDAT', 'IEND']));
    });

    test('throws on non-APNG PNG (no acTL chunk)', () {
      final plainPng = createTestPng();
      expect(
        () => decodeApng(plainPng),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
```

**Step 2: Run tests to verify they fail**

Run: `flutter test test/apng/decoder_test.dart`
Expected: FAIL — cannot find `decoder.dart`.

**Step 3: Implement decoder.dart**

Create `lib/src/apng/decoder.dart`:

```dart
import 'dart:typed_data';

import 'chunks.dart';

/// Result of decoding an APNG file.
class ApngResult {
  ApngResult({
    required this.frames,
    required this.frameDelayMs,
  });

  /// Individual PNG frames as byte arrays.
  final List<Uint8List> frames;

  /// Delay between frames in milliseconds (from first fcTL).
  final int frameDelayMs;
}

/// Decodes an APNG file into individual PNG frames.
///
/// Throws [FormatException] if the input is not a valid APNG
/// (i.e., a plain PNG without an acTL chunk).
ApngResult decodeApng(Uint8List apngBytes) {
  final chunks = parsePngChunks(apngBytes);

  // Verify this is an APNG (has acTL)
  final acTLIndex = chunks.indexWhere((c) => c.type == 'acTL');
  if (acTLIndex == -1) {
    throw FormatException('Not an APNG file: missing acTL chunk');
  }

  final acTLView = ByteData.sublistView(chunks[acTLIndex].data);
  final numFrames = acTLView.getUint32(0);

  // Get IHDR for reconstructing frames
  final ihdr = chunks.firstWhere((c) => c.type == 'IHDR');

  // Read frame delay from first fcTL
  final firstFcTL = chunks.firstWhere((c) => c.type == 'fcTL');
  final fcTLView = ByteData.sublistView(firstFcTL.data);
  final delayNum = fcTLView.getUint16(20);
  final delayDen = fcTLView.getUint16(22);
  final frameDelayMs = delayDen > 0 ? (delayNum * 1000) ~/ delayDen : delayNum;

  // Walk through chunks and collect frames
  final frames = <Uint8List>[];
  List<PngChunk>? currentFrameIdats;

  for (int i = 0; i < chunks.length; i++) {
    final chunk = chunks[i];

    if (chunk.type == 'fcTL') {
      // If we have accumulated IDATs from a previous frame, finalize it
      if (currentFrameIdats != null) {
        frames.add(_buildFramePng(ihdr, currentFrameIdats));
      }
      currentFrameIdats = [];
    } else if (chunk.type == 'IDAT' && currentFrameIdats != null) {
      currentFrameIdats.add(chunk);
    } else if (chunk.type == 'fdAT' && currentFrameIdats != null) {
      // fdAT data = sequence_number(4) + IDAT data
      // Convert to IDAT by stripping the sequence number
      final idatData = Uint8List.sublistView(chunk.data, 4);
      currentFrameIdats.add(PngChunk('IDAT', idatData));
    }
  }

  // Finalize last frame
  if (currentFrameIdats != null) {
    frames.add(_buildFramePng(ihdr, currentFrameIdats));
  }

  if (frames.length != numFrames) {
    throw FormatException(
      'Expected $numFrames frames from acTL but found ${frames.length}',
    );
  }

  return ApngResult(frames: frames, frameDelayMs: frameDelayMs);
}

/// Reconstructs a standalone PNG from IHDR + IDAT chunks.
Uint8List _buildFramePng(PngChunk ihdr, List<PngChunk> idatChunks) {
  return buildPng([
    ihdr,
    ...idatChunks,
    PngChunk('IEND', Uint8List(0)),
  ]);
}
```

**Step 4: Run tests to verify they pass**

Run: `flutter test test/apng/decoder_test.dart`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/src/apng/decoder.dart test/apng/decoder_test.dart
git commit -m "feat: add APNG decoder"
```

---

### Task 5: APNG Round-Trip Test

Verifies that encoding then decoding produces frames with identical pixel data.

**Files:**
- Create: `test/apng/round_trip_test.dart`
- Create: `test/helpers/test_png.dart` (extract shared helper)

**Step 1: Extract test helper**

Create `test/helpers/test_png.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_golden_animation/src/apng/chunks.dart';

/// Creates a minimal valid 1x1 RGBA PNG with the given color.
Uint8List createTestPng({
  int red = 255,
  int green = 0,
  int blue = 0,
  int alpha = 255,
}) {
  final builder = BytesBuilder();
  builder.add(pngSignature);

  // IHDR: 1x1, 8-bit RGBA
  final ihdrData = Uint8List(13);
  final ihdrView = ByteData.sublistView(ihdrData);
  ihdrView.setUint32(0, 1);
  ihdrView.setUint32(4, 1);
  ihdrData[8] = 8;
  ihdrData[9] = 6;
  ihdrData[10] = 0;
  ihdrData[11] = 0;
  ihdrData[12] = 0;
  builder.add(PngChunk('IHDR', ihdrData).toBytes());

  // IDAT: zlib-compressed row (filter=none + RGBA pixel)
  final rawRow = Uint8List.fromList([0, red, green, blue, alpha]);
  final compressed = ZLibCodec(level: 0).encode(rawRow);
  builder.add(PngChunk('IDAT', Uint8List.fromList(compressed)).toBytes());

  // IEND
  builder.add(PngChunk('IEND', Uint8List(0)).toBytes());

  return Uint8List.fromList(builder.toBytes());
}
```

**Step 2: Update encoder_test.dart and decoder_test.dart to use shared helper**

Replace the inline `createTestPng` and `_zlibCompress` in both test files with:

```dart
import '../helpers/test_png.dart';
```

Remove the duplicated function definitions and the `dart:io` import from those files.

**Step 3: Write round-trip test**

Create `test/apng/round_trip_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/apng/encoder.dart';
import 'package:flutter_golden_animation/src/apng/decoder.dart';
import '../helpers/test_png.dart';

void main() {
  group('APNG round-trip', () {
    test('single frame survives encode-decode', () {
      final original = createTestPng(red: 100, green: 150, blue: 200);
      final apng = encodeApng(frames: [original], frameDelayMs: 100);
      final result = decodeApng(apng);

      expect(result.frames.length, equals(1));
      expect(result.frameDelayMs, equals(100));
      // The decoded frame should be byte-identical to the original
      expect(result.frames[0], equals(original));
    });

    test('multiple frames survive encode-decode', () {
      final frames = [
        createTestPng(red: 255, green: 0, blue: 0),
        createTestPng(red: 0, green: 255, blue: 0),
        createTestPng(red: 0, green: 0, blue: 255),
      ];
      final apng = encodeApng(frames: frames, frameDelayMs: 200);
      final result = decodeApng(apng);

      expect(result.frames.length, equals(3));
      expect(result.frameDelayMs, equals(200));
      for (int i = 0; i < 3; i++) {
        expect(result.frames[i], equals(frames[i]));
      }
    });

    test('frame delay is preserved', () {
      final frame = createTestPng();
      final apng = encodeApng(frames: [frame], frameDelayMs: 42);
      final result = decodeApng(apng);
      expect(result.frameDelayMs, equals(42));
    });
  });
}
```

**Step 4: Run all APNG tests**

Run: `flutter test test/apng/`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add test/helpers/test_png.dart test/apng/round_trip_test.dart test/apng/encoder_test.dart test/apng/decoder_test.dart
git commit -m "feat: add round-trip test and extract shared test helper"
```

---

### Task 6: Frame Comparator (Pixel Diff)

Compares two PNG frames pixel-by-pixel and returns the diff percentage.

**Files:**
- Create: `lib/src/diff/frame_comparator.dart`
- Create: `test/diff/frame_comparator_test.dart`

**Step 1: Write the failing tests**

Create `test/diff/frame_comparator_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/diff/frame_comparator.dart';
import '../helpers/test_png.dart';

void main() {
  group('FrameComparisonResult', () {
    test('identical frames produce 0% diff and passed=true', () {
      final frame = createTestPng(red: 128, green: 64, blue: 32);
      final result = compareFrames(frame, frame);

      expect(result.passed, isTrue);
      expect(result.diffPercent, equals(0.0));
    });

    test('different frames produce non-zero diff and passed=false', () {
      final frame1 = createTestPng(red: 255, green: 0, blue: 0);
      final frame2 = createTestPng(red: 0, green: 255, blue: 0);
      final result = compareFrames(frame1, frame2);

      expect(result.passed, isFalse);
      expect(result.diffPercent, greaterThan(0.0));
    });

    test('respects tolerance threshold', () {
      final frame1 = createTestPng(red: 255);
      final frame2 = createTestPng(red: 254); // very small diff
      final result = compareFrames(frame1, frame2, tolerance: 1.0);

      // With 100% tolerance, even different frames pass
      expect(result.passed, isTrue);
    });

    test('zero tolerance fails on any difference', () {
      final frame1 = createTestPng(red: 255);
      final frame2 = createTestPng(red: 254);
      final result = compareFrames(frame1, frame2, tolerance: 0.0);

      expect(result.passed, isFalse);
    });
  });
}
```

**Step 2: Run tests to verify they fail**

Run: `flutter test test/diff/frame_comparator_test.dart`
Expected: FAIL — cannot find `frame_comparator.dart`.

**Step 3: Implement frame_comparator.dart**

Create `lib/src/diff/frame_comparator.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import '../apng/chunks.dart';

/// Result of comparing two PNG frames.
class FrameComparisonResult {
  FrameComparisonResult({
    required this.passed,
    required this.diffPercent,
    required this.diffPixels,
    required this.totalPixels,
  });

  /// Whether the comparison passed (diffPercent <= tolerance).
  final bool passed;

  /// Percentage of pixels that differ (0.0 to 100.0).
  final double diffPercent;

  /// Number of pixels that differ.
  final int diffPixels;

  /// Total number of pixels compared.
  final int totalPixels;
}

/// Compares two PNG frames pixel-by-pixel.
///
/// [tolerance] is the maximum allowed diff percentage (0.0 = pixel-perfect).
/// Returns a [FrameComparisonResult] with the diff details.
FrameComparisonResult compareFrames(
  Uint8List expectedPng,
  Uint8List actualPng, {
  double tolerance = 0.0,
}) {
  final expectedPixels = _decodePngToRgba(expectedPng);
  final actualPixels = _decodePngToRgba(actualPng);

  if (expectedPixels.length != actualPixels.length) {
    return FrameComparisonResult(
      passed: false,
      diffPercent: 100.0,
      diffPixels: expectedPixels.length ~/ 4,
      totalPixels: expectedPixels.length ~/ 4,
    );
  }

  final totalPixels = expectedPixels.length ~/ 4;
  int diffPixels = 0;

  for (int i = 0; i < expectedPixels.length; i += 4) {
    if (expectedPixels[i] != actualPixels[i] ||
        expectedPixels[i + 1] != actualPixels[i + 1] ||
        expectedPixels[i + 2] != actualPixels[i + 2] ||
        expectedPixels[i + 3] != actualPixels[i + 3]) {
      diffPixels++;
    }
  }

  final diffPercent = totalPixels > 0 ? (diffPixels / totalPixels) * 100.0 : 0.0;

  return FrameComparisonResult(
    passed: diffPercent <= tolerance,
    diffPercent: diffPercent,
    diffPixels: diffPixels,
    totalPixels: totalPixels,
  );
}

/// Decodes a PNG file to raw RGBA pixel data.
///
/// This is a minimal decoder that handles the basic PNG format:
/// - Parses IHDR for dimensions
/// - Decompresses IDAT chunks (zlib)
/// - Applies PNG row filters (None, Sub, Up, Average, Paeth)
Uint8List _decodePngToRgba(Uint8List pngBytes) {
  final chunks = parsePngChunks(pngBytes);
  final ihdr = chunks.firstWhere((c) => c.type == 'IHDR');
  final ihdrView = ByteData.sublistView(ihdr.data);
  final width = ihdrView.getUint32(0);
  final height = ihdrView.getUint32(4);
  final bitDepth = ihdr.data[8];
  final colorType = ihdr.data[9];

  if (bitDepth != 8 || colorType != 6) {
    throw FormatException(
      'Only 8-bit RGBA PNGs are supported (got bitDepth=$bitDepth, colorType=$colorType)',
    );
  }

  // Concatenate all IDAT data and decompress
  final compressedBuilder = BytesBuilder();
  for (final chunk in chunks.where((c) => c.type == 'IDAT')) {
    compressedBuilder.add(chunk.data);
  }
  final decompressed = Uint8List.fromList(
    ZLibCodec().decode(compressedBuilder.toBytes()),
  );

  // Each row has a filter byte + width * 4 bytes (RGBA)
  final bytesPerPixel = 4;
  final stride = width * bytesPerPixel;
  final pixels = Uint8List(height * stride);

  for (int y = 0; y < height; y++) {
    final filterByte = decompressed[y * (stride + 1)];
    final rowStart = y * (stride + 1) + 1;
    final outStart = y * stride;

    for (int x = 0; x < stride; x++) {
      final raw = decompressed[rowStart + x];
      final a = x >= bytesPerPixel ? pixels[outStart + x - bytesPerPixel] : 0;
      final b = y > 0 ? pixels[outStart + x - stride] : 0;
      final c_ = (x >= bytesPerPixel && y > 0) ? pixels[outStart + x - stride - bytesPerPixel] : 0;

      switch (filterByte) {
        case 0: // None
          pixels[outStart + x] = raw;
        case 1: // Sub
          pixels[outStart + x] = (raw + a) & 0xFF;
        case 2: // Up
          pixels[outStart + x] = (raw + b) & 0xFF;
        case 3: // Average
          pixels[outStart + x] = (raw + ((a + b) >> 1)) & 0xFF;
        case 4: // Paeth
          pixels[outStart + x] = (raw + _paeth(a, b, c_)) & 0xFF;
        default:
          throw FormatException('Unknown PNG filter type: $filterByte');
      }
    }
  }

  return pixels;
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}
```

**Step 4: Run tests to verify they pass**

Run: `flutter test test/diff/frame_comparator_test.dart`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/src/diff/frame_comparator.dart test/diff/frame_comparator_test.dart
git commit -m "feat: add pixel-level frame comparator"
```

---

### Task 7: Diff Image Generator

Generates a red-overlay diff PNG highlighting changed pixels.

**Files:**
- Create: `lib/src/diff/diff_image.dart`
- Create: `test/diff/diff_image_test.dart`

**Step 1: Write the failing tests**

Create `test/diff/diff_image_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/diff/diff_image.dart';
import 'package:flutter_golden_animation/src/apng/chunks.dart';
import '../helpers/test_png.dart';

void main() {
  group('generateDiffImage', () {
    test('produces a valid PNG', () {
      final frame1 = createTestPng(red: 255, green: 0, blue: 0);
      final frame2 = createTestPng(red: 0, green: 255, blue: 0);

      final diffPng = generateDiffImage(frame1, frame2);

      // Should be a valid PNG
      expect(diffPng.sublist(0, 8), equals(pngSignature));
      final chunks = parsePngChunks(diffPng);
      expect(chunks.map((c) => c.type), containsAll(['IHDR', 'IDAT', 'IEND']));
    });

    test('identical frames produce a transparent diff', () {
      final frame = createTestPng(red: 128, green: 128, blue: 128);

      final diffPng = generateDiffImage(frame, frame);

      // Decode and check that all pixels are transparent/black
      // (no differences to highlight)
      expect(diffPng, isNotNull);
    });

    test('different frames produce non-transparent diff', () {
      final frame1 = createTestPng(red: 255, green: 0, blue: 0);
      final frame2 = createTestPng(red: 0, green: 0, blue: 255);

      final diffPng = generateDiffImage(frame1, frame2);

      // The diff image should exist and be different from a "no diff" image
      expect(diffPng.length, greaterThan(0));
    });
  });
}
```

**Step 2: Run tests to verify they fail**

Run: `flutter test test/diff/diff_image_test.dart`
Expected: FAIL — cannot find `diff_image.dart`.

**Step 3: Implement diff_image.dart**

Create `lib/src/diff/diff_image.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import '../apng/chunks.dart';
import 'frame_comparator.dart' show compareFrames;

/// Generates a diff PNG highlighting pixels that differ between two frames.
///
/// Unchanged pixels are shown at 30% opacity (dimmed).
/// Changed pixels are shown in red (#FF0000) at full opacity.
///
/// Both PNGs must be 8-bit RGBA and the same dimensions.
Uint8List generateDiffImage(Uint8List expectedPng, Uint8List actualPng) {
  final expectedChunks = parsePngChunks(expectedPng);
  final actualChunks = parsePngChunks(actualPng);

  final ihdr = expectedChunks.firstWhere((c) => c.type == 'IHDR');
  final ihdrView = ByteData.sublistView(ihdr.data);
  final width = ihdrView.getUint32(0);
  final height = ihdrView.getUint32(4);

  // Decode both to raw RGBA
  final expectedPixels = _decompressIdat(expectedChunks, width, height);
  final actualPixels = _decompressIdat(actualChunks, width, height);

  // Build diff pixels
  final diffPixels = Uint8List(width * height * 4);
  for (int i = 0; i < diffPixels.length; i += 4) {
    final different = expectedPixels[i] != actualPixels[i] ||
        expectedPixels[i + 1] != actualPixels[i + 1] ||
        expectedPixels[i + 2] != actualPixels[i + 2] ||
        expectedPixels[i + 3] != actualPixels[i + 3];

    if (different) {
      // Red highlight
      diffPixels[i] = 255;     // R
      diffPixels[i + 1] = 0;   // G
      diffPixels[i + 2] = 0;   // B
      diffPixels[i + 3] = 255; // A
    } else {
      // Dimmed original
      diffPixels[i] = expectedPixels[i];
      diffPixels[i + 1] = expectedPixels[i + 1];
      diffPixels[i + 2] = expectedPixels[i + 2];
      diffPixels[i + 3] = (expectedPixels[i + 3] * 0.3).round();
    }
  }

  // Encode back to PNG
  return _encodePng(ihdr, diffPixels, width, height);
}

Uint8List _decompressIdat(List<PngChunk> chunks, int width, int height) {
  final compressedBuilder = BytesBuilder();
  for (final chunk in chunks.where((c) => c.type == 'IDAT')) {
    compressedBuilder.add(chunk.data);
  }
  final decompressed = Uint8List.fromList(
    ZLibCodec().decode(compressedBuilder.toBytes()),
  );

  final stride = width * 4;
  final pixels = Uint8List(height * stride);

  for (int y = 0; y < height; y++) {
    final filterByte = decompressed[y * (stride + 1)];
    final rowStart = y * (stride + 1) + 1;
    final outStart = y * stride;

    for (int x = 0; x < stride; x++) {
      final raw = decompressed[rowStart + x];
      final a = x >= 4 ? pixels[outStart + x - 4] : 0;
      final b = y > 0 ? pixels[outStart + x - stride] : 0;
      final c_ = (x >= 4 && y > 0) ? pixels[outStart + x - stride - 4] : 0;

      pixels[outStart + x] = switch (filterByte) {
        0 => raw,
        1 => (raw + a) & 0xFF,
        2 => (raw + b) & 0xFF,
        3 => (raw + ((a + b) >> 1)) & 0xFF,
        4 => (raw + _paeth(a, b, c_)) & 0xFF,
        _ => throw FormatException('Unknown filter: $filterByte'),
      };
    }
  }

  return pixels;
}

Uint8List _encodePng(PngChunk ihdr, Uint8List pixels, int width, int height) {
  final stride = width * 4;

  // Add filter byte (0 = None) to each row
  final rawData = Uint8List(height * (stride + 1));
  for (int y = 0; y < height; y++) {
    rawData[y * (stride + 1)] = 0; // filter = None
    rawData.setRange(
      y * (stride + 1) + 1,
      y * (stride + 1) + 1 + stride,
      pixels,
      y * stride,
    );
  }

  final compressed = Uint8List.fromList(ZLibCodec(level: 0).encode(rawData));

  return buildPng([
    ihdr,
    PngChunk('IDAT', compressed),
    PngChunk('IEND', Uint8List(0)),
  ]);
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}
```

**Step 4: Run tests to verify they pass**

Run: `flutter test test/diff/diff_image_test.dart`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/src/diff/diff_image.dart test/diff/diff_image_test.dart
git commit -m "feat: add diff image generator with red overlay"
```

---

### Task 8: Report Generator

Generates a text summary of which frames differ and by how much.

**Files:**
- Create: `lib/src/diff/report.dart`
- Create: `test/diff/report_test.dart`

**Step 1: Write the failing tests**

Create `test/diff/report_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/diff/report.dart';
import 'package:flutter_golden_animation/src/diff/frame_comparator.dart';

void main() {
  group('generateReport', () {
    test('reports all frames passing', () {
      final results = [
        FrameComparisonResult(passed: true, diffPercent: 0.0, diffPixels: 0, totalPixels: 100),
        FrameComparisonResult(passed: true, diffPercent: 0.0, diffPixels: 0, totalPixels: 100),
      ];

      final report = generateReport(results, 'button_press.apng');

      expect(report, contains('0 of 2 frames differ'));
    });

    test('reports failing frames with diff percentages', () {
      final results = [
        FrameComparisonResult(passed: true, diffPercent: 0.0, diffPixels: 0, totalPixels: 100),
        FrameComparisonResult(passed: false, diffPercent: 0.3, diffPixels: 3, totalPixels: 1000),
        FrameComparisonResult(passed: true, diffPercent: 0.0, diffPixels: 0, totalPixels: 100),
        FrameComparisonResult(passed: false, diffPercent: 1.2, diffPixels: 12, totalPixels: 1000),
      ];

      final report = generateReport(results, 'button_press.apng');

      expect(report, contains('2 of 4 frames differ'));
      expect(report, contains('Frame 1'));
      expect(report, contains('0.3%'));
      expect(report, contains('Frame 3'));
      expect(report, contains('1.2%'));
    });

    test('includes golden file name', () {
      final results = [
        FrameComparisonResult(passed: false, diffPercent: 5.0, diffPixels: 50, totalPixels: 1000),
      ];

      final report = generateReport(results, 'goldens/my_test.apng');

      expect(report, contains('goldens/my_test.apng'));
    });
  });
}
```

**Step 2: Run tests to verify they fail**

Run: `flutter test test/diff/report_test.dart`
Expected: FAIL — cannot find `report.dart`.

**Step 3: Implement report.dart**

Create `lib/src/diff/report.dart`:

```dart
import 'frame_comparator.dart';

/// Generates a human-readable text report of frame comparison results.
String generateReport(List<FrameComparisonResult> results, String goldenName) {
  final failingFrames = <int>[];
  for (int i = 0; i < results.length; i++) {
    if (!results[i].passed) {
      failingFrames.add(i);
    }
  }

  final buffer = StringBuffer();
  buffer.writeln('Golden animation comparison: $goldenName');
  buffer.writeln('${failingFrames.length} of ${results.length} frames differ.');

  if (failingFrames.isNotEmpty) {
    buffer.writeln('');
    for (final i in failingFrames) {
      final r = results[i];
      buffer.writeln(
        'Frame $i: ${r.diffPercent.toStringAsFixed(1)}% diff '
        '(${r.diffPixels} of ${r.totalPixels} pixels)',
      );
    }
  }

  return buffer.toString();
}
```

**Step 4: Run tests to verify they pass**

Run: `flutter test test/diff/report_test.dart`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/src/diff/report.dart test/diff/report_test.dart
git commit -m "feat: add text report generator for frame diffs"
```

---

### Task 9: AnimationRecorder

The core user-facing class that captures animation frames.

**Files:**
- Create: `lib/src/recorder.dart`
- Create: `test/recorder_test.dart`

**Step 1: Write the failing tests**

Create `test/recorder_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/recorder.dart';
import 'package:flutter_golden_animation/src/apng/chunks.dart';

void main() {
  group('AnimationRecorder', () {
    testWidgets('captures frames from an animating widget', (tester) async {
      // A simple widget that animates opacity over 500ms
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
```

**Step 2: Run tests to verify they fail**

Run: `flutter test test/recorder_test.dart`
Expected: FAIL — cannot find `recorder.dart`.

**Step 3: Implement recorder.dart**

Create `lib/src/recorder.dart`:

```dart
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apng/encoder.dart';

/// Records animation frames from a widget test.
///
/// Usage:
/// ```dart
/// final recorder = AnimationRecorder(tester);
/// await recorder.record(
///   interaction: () => tester.tap(find.byType(MyButton)),
///   duration: Duration(milliseconds: 500),
///   frameRate: 60,
/// );
/// await recorder.compareWithGolden('goldens/my_animation.apng');
/// ```
class AnimationRecorder {
  AnimationRecorder(this._tester);

  final WidgetTester _tester;
  final List<Uint8List> _frames = [];
  int _frameDelayMs = 16;

  /// The captured frames as PNG byte arrays.
  List<Uint8List> get frames => List.unmodifiable(_frames);

  /// Records animation frames.
  ///
  /// [interaction] is called before frame recording starts (e.g., to tap a button).
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

    // Run the interaction first
    if (interaction != null) {
      await interaction();
    }

    // Capture frames
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
  /// Uses the registered [goldenFileComparator] for comparison.
  /// When running with `--update-goldens`, writes the new APNG instead.
  Future<void> compareWithGolden(String goldenPath) async {
    final apngBytes = toApng();
    final uri = Uri.parse(goldenPath);

    if (autoUpdateGoldenFiles) {
      await goldenFileComparator.update(uri, apngBytes);
    } else {
      final bool passed = await goldenFileComparator.compare(apngBytes, uri);
      if (!passed) {
        throw TestFailure('Animation golden test failed for $goldenPath');
      }
    }
  }

  Future<Uint8List> _captureFrame() async {
    // Find the topmost RepaintBoundary
    final element = _tester.binding.rootElement!;
    final renderObject = _findRepaintBoundary(element);

    if (renderObject == null) {
      throw StateError(
        'No RepaintBoundary found. Wrap your widget in a RepaintBoundary.',
      );
    }

    final image = await renderObject.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

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
```

**Step 4: Run tests to verify they pass**

Run: `flutter test test/recorder_test.dart`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/src/recorder.dart test/recorder_test.dart
git commit -m "feat: add AnimationRecorder for frame capture"
```

---

### Task 10: ApngGoldenComparator

The custom `GoldenFileComparator` that handles APNG comparison and failure artifacts.

**Files:**
- Create: `lib/src/comparator.dart`
- Create: `test/comparator_test.dart`

**Step 1: Write the failing tests**

Create `test/comparator_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/comparator.dart';
import 'package:flutter_golden_animation/src/apng/encoder.dart';
import '../helpers/test_png.dart';

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

      // Write the golden file
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
        // Expected — now check failure artifacts
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
```

**Step 2: Run tests to verify they fail**

Run: `flutter test test/comparator_test.dart`
Expected: FAIL — cannot find `comparator.dart`.

**Step 3: Implement comparator.dart**

Create `lib/src/comparator.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apng/decoder.dart';
import 'apng/encoder.dart';
import 'diff/diff_image.dart';
import 'diff/frame_comparator.dart';
import 'diff/report.dart';

/// Custom [GoldenFileComparator] that compares APNG animation goldens
/// frame-by-frame and generates detailed failure artifacts.
class ApngGoldenComparator extends GoldenFileComparator {
  ApngGoldenComparator({
    required this.testDir,
    this.tolerance = 0.0,
  });

  /// Base directory for resolving golden file paths.
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

    // Decode both APNGs
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
      // Generate failure artifacts
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

    // Write expected and actual
    await File('${failDir.path}/expected.apng').writeAsBytes(golden);
    await File('${failDir.path}/actual.apng').writeAsBytes(test);

    // Write diff APNG if we have diff frames
    if (diffFrames != null && diffFrames.isNotEmpty) {
      final diffApng = encodeApng(
        frames: diffFrames,
        frameDelayMs: frameDelayMs ?? 100,
      );
      await File('${failDir.path}/diff.apng').writeAsBytes(diffApng);

      // Write individual diff PNGs for failing frames
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

    // Write report
    if (results != null) {
      final report = generateReport(results, goldenUri.pathSegments.last);
      await File('${failDir.path}/report.txt').writeAsString(report);
    } else if (message != null) {
      await File('${failDir.path}/report.txt').writeAsString(message);
    }
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `flutter test test/comparator_test.dart`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/src/comparator.dart test/comparator_test.dart
git commit -m "feat: add ApngGoldenComparator with failure artifacts"
```

---

### Task 11: Public API & Setup Function

Wire everything together in the barrel export and add the `setupGoldenAnimationCompare()` convenience function.

**Files:**
- Modify: `lib/flutter_golden_animation.dart`

**Step 1: Update barrel export**

```dart
library flutter_golden_animation;

export 'src/recorder.dart' show AnimationRecorder;
export 'src/comparator.dart' show ApngGoldenComparator;
export 'src/setup.dart' show setupGoldenAnimationCompare;
```

**Step 2: Create setup.dart**

Create `lib/src/setup.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'comparator.dart';

/// Registers the [ApngGoldenComparator] as the golden file comparator.
///
/// Call this at the top of your test's `main()` function:
///
/// ```dart
/// void main() {
///   setupGoldenAnimationCompare();
///   // ... your tests
/// }
/// ```
///
/// [tolerance] is the maximum allowed diff percentage per frame
/// (0.0 = pixel-perfect, which is the default).
void setupGoldenAnimationCompare({double tolerance = 0.0}) {
  final testDir = Directory.current.uri;
  goldenFileComparator = ApngGoldenComparator(
    testDir: testDir,
    tolerance: tolerance,
  );
}
```

**Step 3: Run all tests**

Run: `flutter test`
Expected: All tests PASS.

**Step 4: Run flutter analyze**

Run: `flutter analyze`
Expected: No issues found.

**Step 5: Commit**

```bash
git add lib/flutter_golden_animation.dart lib/src/setup.dart
git commit -m "feat: add public API barrel export and setup function"
```

---

### Task 12: Example Test

A working example that developers can copy as a starting point.

**Files:**
- Create: `example/test/example_animation_test.dart`
- Create: `example/pubspec.yaml`
- Create: `example/lib/example_button.dart`

**Step 1: Create example pubspec**

Create `example/pubspec.yaml`:

```yaml
name: flutter_golden_animation_example
description: Example usage of flutter_golden_animation

environment:
  sdk: ^3.7.1
  flutter: ">=3.29.0"

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_golden_animation:
    path: ../
```

**Step 2: Create example widget**

Create `example/lib/example_button.dart`:

```dart
import 'package:flutter/material.dart';

class ExampleButton extends StatefulWidget {
  const ExampleButton({super.key});

  @override
  State<ExampleButton> createState() => _ExampleButtonState();
}

class _ExampleButtonState extends State<ExampleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _pressed = !_pressed),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 120,
        height: 48,
        decoration: BoxDecoration(
          color: _pressed ? Colors.green : Colors.blue,
          borderRadius: BorderRadius.circular(_pressed ? 24 : 8),
        ),
        alignment: Alignment.center,
        child: Text(
          _pressed ? 'Done' : 'Press me',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
```

**Step 3: Create example test**

Create `example/test/example_animation_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/flutter_golden_animation.dart';
import 'package:flutter_golden_animation_example/example_button.dart';

void main() {
  setupGoldenAnimationCompare();

  testWidgets('ExampleButton press animation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              child: const ExampleButton(),
            ),
          ),
        ),
      ),
    );

    final recorder = AnimationRecorder(tester);

    await recorder.record(
      interaction: () => tester.tap(find.byType(ExampleButton)),
      duration: const Duration(milliseconds: 300),
      frameRate: 10,
    );

    await recorder.compareWithGolden('goldens/example_button_press.apng');
  });
}
```

**Step 4: Run pub get in example**

Run: `cd example && flutter pub get`
Expected: Dependencies resolve successfully.

**Step 5: Generate the initial golden**

Run: `cd example && flutter test --update-goldens`
Expected: Golden file created at `example/goldens/example_button_press.apng`.

**Step 6: Verify the test passes**

Run: `cd example && flutter test`
Expected: All tests PASS.

**Step 7: Commit**

```bash
git add example/
git commit -m "feat: add example project with animation golden test"
```

---

### Task 13: README

**Files:**
- Create: `README.md`

**Step 1: Write README.md**

Write a README with:
- Package description (2-3 sentences)
- Installation instructions (pubspec dependency)
- Quick start example (the core test pattern)
- API reference (AnimationRecorder, setupGoldenAnimationCompare, compareWithGolden)
- How golden updates work (`flutter test --update-goldens`)
- What failure artifacts look like (the failures/ directory structure)

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```
