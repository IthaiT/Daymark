/// Lossless source information for an imported Markdown node.
class ItemSource {
  const ItemSource({
    required this.directory,
    required this.path,
    required this.kind,
    required this.order,
    required this.raw,
    this.missing = false,
  });
  final String directory;
  final String path;
  final String kind;
  final int order;
  final String raw;
  final bool missing;

  ItemSource asMissing() => ItemSource(
    directory: directory,
    path: path,
    kind: kind,
    order: order,
    raw: raw,
    missing: true,
  );

  factory ItemSource.fromJson(Map<String, Object?> row) {
    if (row['directory'] is! String ||
        row['path'] is! String ||
        !const ['file', 'task'].contains(row['kind']) ||
        row['order'] is! int ||
        row['raw'] is! String ||
        (row['missing'] != null && row['missing'] is! bool)) {
      throw const FormatException('事项来源格式不正确。');
    }
    return ItemSource(
      directory: row['directory']! as String,
      path: row['path']! as String,
      kind: row['kind']! as String,
      order: row['order']! as int,
      raw: row['raw']! as String,
      missing: row['missing'] as bool? ?? false,
    );
  }
  Map<String, Object?> toJson() => {
    'directory': directory,
    'path': path,
    'kind': kind,
    'order': order,
    'raw': raw,
    'missing': missing,
  };
  @override
  bool operator ==(Object other) =>
      other is ItemSource &&
      directory == other.directory &&
      path == other.path &&
      kind == other.kind &&
      order == other.order &&
      raw == other.raw &&
      missing == other.missing;
  @override
  int get hashCode => Object.hash(directory, path, kind, order, raw, missing);
}
