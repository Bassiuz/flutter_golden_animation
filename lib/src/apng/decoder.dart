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
