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
