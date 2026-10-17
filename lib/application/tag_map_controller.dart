import 'package:flutter/foundation.dart';

import '../application/journal_controller.dart';
import '../domain/model.dart';
import '../domain/tag_tree.dart';
import '../domain/unicode.dart';

/// Holds tag-map edits in memory and commits them through [Store.replaceTags].
/// The web view never writes files and never owns the persisted format.
class TagMapController extends ChangeNotifier {
  TagMapController(this.journal)
    : _baseline = TagTree.fromTags(journal.store.tags.values),
      _draft = TagTree.fromTags(journal.store.tags.values);
  final JournalController journal;
  TagTree _baseline;
  TagTree _draft;
  bool _saving = false;

  TagTree get draft => _draft;
  bool get saving => _saving;
  bool get dirty => !_draft.sameAs(_baseline);

  TagNode? node(String id) {
    TagNode? find(List<TagNode> nodes) {
      for (final node in nodes) {
        if (node.id == id) return node;
        final child = find(node.children);
        if (child != null) return child;
      }
      return null;
    }

    return find(_draft.children);
  }

  /// Re-reads tags changed outside the map (the journal sidebar) while a draft
  /// is retained. Newly added tags are merged; deleted leaf tags disappear.
  bool syncFromStore() {
    final latest = TagTree.fromTags(journal.store.tags.values);
    if (latest.sameAs(_baseline)) return false;
    if (!dirty) {
      _baseline = latest;
      _draft = latest;
      notifyListeners();
      return true;
    }
    _draft = _mergeExternal(_draft, latest);
    _baseline = latest;
    notifyListeners();
    return true;
  }

  String? parentIdOf(String id) {
    String? find(List<TagNode> nodes, String? parentId) {
      for (final node in nodes) {
        if (node.id == id) return parentId;
        final found = find(node.children, node.id);
        if (found != null) return found;
      }
      return null;
    }

    return find(_draft.children, null);
  }

  /// Sibling names must stay unique under the same parent, matching
  /// [Store.validateTags].
  String? validateName(String? parentId, String name, {String? ignoreId}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '请输入标签名称。';
    final parent = parentId == null || parentId == tagTreeRootId
        ? null
        : node(parentId);
    final siblings = parent == null ? _draft.children : parent.children;
    final folded = caseFold(trimmed);
    if (siblings.any(
      (sibling) =>
          sibling.id != ignoreId && caseFold(sibling.name.trim()) == folded,
    )) {
      return '同一个父标签下不能有重名标签。';
    }
    return null;
  }

  TagTree _mergeExternal(TagTree local, TagTree latest) {
    final previous = {for (final tag in _allTags(_baseline)) tag.id: tag};
    final current = {for (final tag in _allTags(latest)) tag.id: tag};
    final removed = previous.keys
        .where((id) => !current.containsKey(id))
        .toSet();
    final present = <String>{};

    List<TagNode> filter(List<TagNode> nodes) {
      final result = <TagNode>[];
      for (final node in nodes) {
        final children = filter(node.children);
        if (!node.isNew && removed.contains(node.id)) {
          result.addAll(children);
          continue;
        }
        present.add(node.id);
        result.add(TagNode(id: node.id, name: node.name, children: children));
      }
      return result;
    }

    final merged = filter(local.children);
    final added = current.values.where(
      (tag) => !previous.containsKey(tag.id) && !present.contains(tag.id),
    );
    for (final tag in added) {
      final node = TagNode(id: tag.id, name: tag.name);
      if (tag.parentId == null) {
        merged.add(node);
        present.add(tag.id);
        continue;
      }
      final target = _findIn(merged, tag.parentId!);
      if (target == null) {
        merged.add(node);
      } else {
        target.children.add(node);
      }
      present.add(tag.id);
    }
    // Rebuild once after inserting externally added tags.
    return TagTree.fromJson({
      'id': tagTreeRootId,
      'name': tagTreeRootName,
      'children': [for (final node in merged) _toJsonWithChildren(node)],
    });
  }

  static Iterable<Tag> _allTags(TagTree tree) sync* {
    Iterable<Tag> visit(List<TagNode> nodes, String? parentId) sync* {
      for (final node in nodes) {
        yield Tag(node.id, node.name, parentId);
        yield* visit(node.children, node.id);
      }
    }

    yield* visit(tree.children, null);
  }

  static TagNode? _findIn(List<TagNode> nodes, String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
      final child = _findIn(node.children, id);
      if (child != null) return child;
    }
    return null;
  }

  static Map<String, Object?> _toJsonWithChildren(TagNode node) => {
    'id': node.id,
    'name': node.name,
    'children': [for (final child in node.children) _toJsonWithChildren(child)],
  };

  /// Applies the tree reported by the web view. Malformed input is rejected so
  /// a scripting failure can never replace the in-memory draft with junk.
  void applyFromWeb(Object? value) => applyTree(TagTree.fromJson(value));

  void applyTree(TagTree tree) {
    if (tree.sameAs(_draft)) return;
    _draft = tree;
    notifyListeners();
  }

  /// Why [id] cannot be deleted, or null when deletion is allowed. The store
  /// repeats these checks before writing; this keeps the UI understandable.
  String? deleteBlocker(String id) {
    if (id == tagTreeRootId) return '虚拟根节点不能删除。';
    final node = this.node(id);
    if (node == null) return '标签不存在。';
    if (node.children.isNotEmpty) return '请先删除或移动它的子标签。';
    final count =
        journal.store.events.values.where((event) => event.tagId == id).length +
        journal.drafts.values.where((event) => event.tagId == id).length;
    if (count > 0) return '此标签还有 $count 个事件，请先给这些事件更换标签。';
    return null;
  }

  Future<TagTree> save() async {
    if (_saving) throw const FormatException('正在保存标签，请稍候。');
    if (!dirty) return _draft;
    _saving = true;
    notifyListeners();
    try {
      final plan = _draft.toTagMap(journal.store.tags);
      await journal.store.replaceTags(plan.tags);
      final saved = TagTree.fromTags(journal.store.tags.values);
      _baseline = saved;
      _draft = saved;
      journal.notifyListeners();
      return saved;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
