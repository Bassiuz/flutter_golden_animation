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
