import 'dart:io';

/// Generates an HTML viewer file that displays all APNG files in a directory.
///
/// The viewer shows each APNG with its filename, rendered inline.
/// Opening this file in a browser (or VS Code's built-in preview) plays
/// all the animations — much easier than opening individual APNG files.
Future<void> generateViewer(Directory directory) async {
  final apngFiles = directory
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.apng'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (apngFiles.isEmpty) return;

  final dirName = directory.uri.pathSegments
      .where((s) => s.isNotEmpty)
      .last;

  final buffer = StringBuffer();
  buffer.writeln('<!DOCTYPE html>');
  buffer.writeln('<html lang="en">');
  buffer.writeln('<head>');
  buffer.writeln('<meta charset="UTF-8">');
  buffer.writeln('<title>Golden Animations — $dirName</title>');
  buffer.writeln('<style>');
  buffer.writeln('  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #1a1a2e; color: #e0e0e0; margin: 0; padding: 24px; }');
  buffer.writeln('  h1 { font-size: 20px; font-weight: 600; margin-bottom: 24px; color: #fff; }');
  buffer.writeln('  .grid { display: flex; flex-wrap: wrap; gap: 24px; }');
  buffer.writeln('  .card { background: #16213e; border: 1px solid #0f3460; border-radius: 12px; padding: 16px; display: flex; flex-direction: column; align-items: center; }');
  buffer.writeln('  .card img { max-width: 400px; background: #0a0a1a; border-radius: 8px; image-rendering: pixelated; }');
  buffer.writeln('  .card .label { margin-top: 12px; font-size: 13px; font-family: monospace; color: #a0a0b0; }');
  buffer.writeln('</style>');
  buffer.writeln('</head>');
  buffer.writeln('<body>');
  buffer.writeln('<h1>$dirName</h1>');
  buffer.writeln('<div class="grid">');

  for (final file in apngFiles) {
    final fileName = file.uri.pathSegments.last;
    buffer.writeln('  <div class="card">');
    buffer.writeln('    <img src="$fileName" alt="$fileName">');
    buffer.writeln('    <div class="label">$fileName</div>');
    buffer.writeln('  </div>');
  }

  buffer.writeln('</div>');
  buffer.writeln('</body>');
  buffer.writeln('</html>');

  await File('${directory.path}/viewer.html')
      .writeAsString(buffer.toString(), flush: true);
}
