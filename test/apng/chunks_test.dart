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
