import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/src/apng/decoder.dart';
import 'package:flutter_golden_animation/src/apng/encoder.dart';
import 'package:flutter_golden_animation/src/apng/chunks.dart';

Uint8List createTestPng({int red = 255, int green = 0, int blue = 0, int alpha = 255}) {
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
