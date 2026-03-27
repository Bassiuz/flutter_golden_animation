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
    final data = Uint8List.fromList(bytes.sublist(8, 8 + length));

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
List<PngChunk> parsePngChunks(Uint8List pngBytes, {bool validateCrc = false}) {
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
    final chunkSize = 12 + length;

    if (offset + chunkSize > pngBytes.length) {
      throw FormatException('Chunk extends beyond file end at offset $offset');
    }

    final chunkBytes =
        Uint8List.sublistView(pngBytes, offset, offset + chunkSize);
    chunks.add(PngChunk.fromBytes(chunkBytes, validateCrc: validateCrc));
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
