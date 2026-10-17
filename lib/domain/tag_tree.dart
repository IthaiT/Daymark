import 'package:uuid/uuid.dart';

import 'model.dart';
import 'unicode.dart';

/// Fixed identity of the "all tags" root. It never becomes a persisted tag;
/// real tags always live below it.
const tagTreeRootId = 'daymark:root';
const tagTreeRootName = 'Daymark';

/// Nodes created inside the web view are identified until saving assigns the
/// final stable tag id.
const newTagIdPrefix = 'new:';
const _maxDepth = 64;
const _maxNodes = 10000;

/// Immutable tag tree used by the mind map. Siblings follow the same ordering
/// as [Store.orderedTags]: case-folded names compared by Unicode code point.
///
/// The full tree has a virtual [tagTreeRootId] root. [subtree] returns a view
/// whose root is a real tag; such a view can only be merged with
/// [replaceSubtree], never written with [toTagMap].
class TagTree {
  const TagTree._(this.root);
  final TagNode root;

  List<TagNode> get children => root.children;
  bool get isEmpty => root.children.isEmpty;
  bool get isVirtualRoot => root.id == tagTreeRootId;

  factory TagTree.fromTags(Iterable<Tag> tags) {
    final children = <String?, List<Tag>>{};
    for (final tag in tags) {
      (children[tag.parentId] ??= []).add(tag);
    }
    for (final siblings in children.values) {
      siblings.sort(compareTagDisplayOrder);
    }
    List<TagNode> build(String? parentId) => [
      for (final tag in children[parentId] ?? const <Tag>[])
        TagNode(id: tag.id, name: tag.name, children: build(tag.id)),
    ];
    return TagTree._(
      TagNode(id: tagTreeRootId, name: tagTreeRootName, children: build(null)),
    );
  }

  /// Parses the tree produced by the web view. With [expectedRootId] the tree
  /// is a view rooted at that real tag (or at [tagTreeRootId] for "all tags").
  factory TagTree.fromJson(Object? value, {String? expectedRootId}) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('标签导图数据格式不正确。');
    }
    final expected = expectedRootId ?? tagTreeRootId;
    if (value['id'] != expected || value['children'] is! List<Object?>) {
      throw const FormatException('标签导图的根节点不正确。');
    }
    if (expected == tagTreeRootId && value['name'] != tagTreeRootName) {
      throw const FormatException('标签导图的根节点不正确。');
    }
    final seen = <String>{};
    var count = 0;

    TagNode parse(Object? raw, int depth, {bool isRoot = false}) {
      if (raw is! Map<String, Object?>) {
        throw const FormatException('标签导图节点格式不正确。');
      }
      final id = raw['id'];
      final name = raw['name'];
      final children = raw['children'];
      if (id is! String ||
          name is! String ||
          children is! List<Object?> ||
          id.isEmpty ||
          depth > _maxDepth) {
        throw const FormatException('标签导图节点格式不正确。');
      }
      if ((!isRoot && id == tagTreeRootId) || !seen.add(id)) {
        throw const FormatException('标签导图包含重复的节点。');
      }
      if (id.startsWith(newTagIdPrefix) && id.length == newTagIdPrefix.length) {
        throw const FormatException('标签导图包含无效的新节点。');
      }
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        throw const FormatException('标签名称不能为空。');
      }
      count++;
      if (count > _maxNodes) {
        throw const FormatException('标签数量过多。');
      }
      return TagNode(
        id: id,
        name: trimmed,
        children: [for (final child in children) parse(child, depth + 1)],
      );
    }

    final parsed = parse(value, 0, isRoot: true);
    if (expected != tagTreeRootId) return TagTree._(parsed);
    return TagTree._(
      TagNode(
        id: tagTreeRootId,
        name: tagTreeRootName,
        children: parsed.children,
      ),
    );
  }

  TagNode? find(String id) {
    TagNode? visit(List<TagNode> nodes) {
      for (final node in nodes) {
        if (node.id == id) return node;
        final found = visit(node.children);
        if (found != null) return found;
      }
      return null;
    }

    return visit(root.children);
  }

  String? parentIdOf(String id) {
    String? visit(List<TagNode> nodes, String? parentId) {
      for (final node in nodes) {
        if (node.id == id) return parentId;
        final found = visit(node.children, node.id);
        if (found != null) return found;
      }
      return null;
    }

    return visit(root.children, null);
  }

  /// A view whose root is the real tag [id]. The root's own parent is not part
  /// of the view and is preserved by [replaceSubtree].
  TagTree? subtree(String id) {
    if (id == tagTreeRootId) return this;
    final node = find(id);
    return node == null ? null : TagTree._(node);
  }

  /// All real tags in display order with their depth, for root pickers.
  List<(TagNode, int)> flatten() {
    final result = <(TagNode, int)>[];
    void visit(List<TagNode> nodes, int depth) {
      for (final node in nodes) {
        result.add((node, depth));
        visit(node.children, depth + 1);
      }
    }

    visit(root.children, 0);
    return result;
  }

  /// Replaces the edited subtree in this full tree. Tags outside the view are
  /// untouched, and a view may not contain tags from outside its original
  /// subtree.
  TagTree replaceSubtree(TagTree view) {
    if (view.isVirtualRoot) {
      return TagTree._(
        TagNode(
          id: tagTreeRootId,
          name: tagTreeRootName,
          children: view.root.children,
        ),
      );
    }
    final rootId = view.root.id;
    final original = find(rootId);
    if (original == null) {
      throw const FormatException('根标签不存在。');
    }
    final allowed = <String>{};
    void collect(TagNode node) {
      if (!node.isNew) allowed.add(node.id);
      for (final child in node.children) {
        collect(child);
      }
    }

    collect(original);
    void check(TagNode node) {
      if (!node.isNew && !allowed.contains(node.id)) {
        throw const FormatException('导图包含当前根标签之外的标签。');
      }
      for (final child in node.children) {
        check(child);
      }
    }

    check(view.root);

    TagNode replace(TagNode node) {
      if (node.id == rootId) {
        return TagNode(
          id: rootId,
          name: view.root.name,
          children: view.root.children,
        );
      }
      return TagNode(
        id: node.id,
        name: node.name,
        children: [for (final child in node.children) replace(child)],
      );
    }

    return TagTree._(
      TagNode(
        id: tagTreeRootId,
        name: tagTreeRootName,
        children: [for (final child in root.children) replace(child)],
      ),
    );
  }

  /// Builds the complete tag map represented by this full tree. Existing tags
  /// keep their ids; new nodes receive generated ids. Validation (duplicate
  /// sibling names, missing parents, cycles) is performed by the store.
  TagTreeSave toTagMap(
    Map<String, Tag> existing, {
    String Function()? createId,
  }) {
    if (!isVirtualRoot) {
      throw StateError('A tag map view cannot be persisted directly.');
    }
    final generator = createId ?? () => const Uuid().v4().replaceAll('-', '');
    final tags = <String, Tag>{};
    final assigned = <String, String>{};
    final known = existing.keys.toSet();

    void visit(List<TagNode> nodes, String? parentId) {
      for (final node in nodes) {
        final isNew = node.id.startsWith(newTagIdPrefix);
        if (!isNew && !known.contains(node.id)) {
          throw const FormatException('标签导图包含不存在的标签。');
        }
        final id = isNew
            ? assigned.putIfAbsent(node.id, () {
                for (var attempt = 0; attempt < 16; attempt++) {
                  final candidate = generator();
                  if (!tags.containsKey(candidate) &&
                      !existing.containsKey(candidate)) {
                    return candidate;
                  }
                }
                throw const FormatException('无法生成唯一的标签 ID。');
              })
            : node.id;
        tags[id] = Tag(id, node.name, parentId);
        visit(node.children, id);
      }
    }

    visit(root.children, null);
    return TagTreeSave(tags, assigned);
  }

  /// Replaces temporary web-view ids with the stable ids assigned on save.
  TagTree mapIds(Map<String, String> ids) {
    if (ids.isEmpty) return this;
    TagNode map(TagNode node) => TagNode(
      id: ids[node.id] ?? node.id,
      name: node.name,
      children: [for (final child in node.children) map(child)],
    );

    return TagTree._(map(root));
  }

  /// Equality of the displayed structure and names.
  bool sameAs(TagTree other) {
    bool equal(TagNode left, TagNode right) {
      if (left.id != right.id ||
          left.name != right.name ||
          left.children.length != right.children.length) {
        return false;
      }
      for (var i = 0; i < left.children.length; i++) {
        if (!equal(left.children[i], right.children[i])) return false;
      }
      return true;
    }

    return equal(root, other.root);
  }

  Map<String, Object?> toJson() => root.toJson();
}

final class TagNode {
  const TagNode({
    required this.id,
    required this.name,
    this.children = const [],
  });
  final String id;
  final String name;
  final List<TagNode> children;
  bool get isNew => id.startsWith(newTagIdPrefix);
  bool get isRoot => id == tagTreeRootId;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'children': [for (final child in children) child.toJson()],
  };
}

final class TagTreeSave {
  const TagTreeSave(this.tags, this.assignedIds);
  final Map<String, Tag> tags;

  /// Temporary web-view node id to the stable tag id written to disk.
  final Map<String, String> assignedIds;
}

int compareTagDisplayOrder(Tag a, Tag b) {
  final result = compareUnicode(
    caseFold(a.name.trim()),
    caseFold(b.name.trim()),
  );
  return result != 0 ? result : compareUnicode(a.id, b.id);
}
