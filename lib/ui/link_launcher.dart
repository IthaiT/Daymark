import 'dart:io';

/// Schemes an outcome link may use. A bare path is accepted as a local file.
const _schemes = {'http', 'https', 'file', 'obsidian', 'mailto'};

/// Whether [raw] is something the system can be asked to open.
bool isOpenableLink(String raw) {
  final link = raw.trim();
  if (link.isEmpty || link.contains('"') || link.contains('\n')) return false;
  final uri = Uri.tryParse(link);
  if (uri == null) return false;
  if (_schemes.contains(uri.scheme)) return true;
  // A Windows path parses as a one-letter scheme, so check the file system.
  return uri.scheme.isEmpty && File(link).existsSync();
}

/// Hands a link to the desktop's default handler: Obsidian, a browser or the
/// file explorer. Returns false when the link looks unsafe or nothing opened.
Future<bool> openExternalLink(String raw) async {
  final link = raw.trim();
  if (!isOpenableLink(link)) return false;
  try {
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', link], runInShell: true);
    } else if (Platform.isMacOS) {
      await Process.run('open', [link]);
    } else {
      await Process.run('xdg-open', [link]);
    }
    return true;
  } on ProcessException {
    return false;
  }
}
