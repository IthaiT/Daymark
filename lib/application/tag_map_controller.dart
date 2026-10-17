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
  String? _rootId;
  bool _saving = false;

  /// Temporary web-view ids to the stable ids assigned by the last save.
  final Map<String, String> _assignedIds = {};

  /// The full tag tree, including tags hidden by the current root view.
  TagTree get draft => _draft;
  bool get saving => _saving;
  bool get dirty => !_draft.sameAs(_baseline);

  /// Null means the "all tags" view; otherwise a real tag is the map root and
  /// only its subtree is shown.
  String? get rootId => _rootId;
  bool get isAllView => _rootId == null;
  TagTree? get view {
    final id = _rootId;
    return id == null ? _draft : _draft.subtree(id);
  }

  TagNode? get rootNode => _rootId == null ? null : _draft.find(_rootId!);
  TagNode? node(String id) => _draft.find(_stableId(id)!);
  String? parentIdOf(String id) => _draft.parentIdOf(_stableId(id)!);
  List<(TagNode, int)> get rootChoices => _draft.flatten();
  Map<String, String> get assignedIds => Map.unmodifiable(_assignedIds);

  String? _stableId(String? id) => id == null ? null : _assignedIds[id] ?? id;

  void setRoot(String? id) {
    id = _stableId(id);
    if (id != null && _draft.find(id) == null) return;
    if (_rootId == id) return;
    _rootId = id;
    notifyListeners();
  }

  void _ensureRoot() {
    final id = _rootId;
    if (id != null && _draft.find(id) == null) _rootId = null;
  }

  /// Re-reads tags changed outside the map (the journal sidebar) while a draft
  /// is retained. Newly added tags are merged; deleted leaf tags disappear.
  bool syncFromStore() {
    final latest = TagTree.fromTags(journal.store.tags.values);
    if (latest.sameAs(_baseline)) return false;
    if (!dirty) {
      _baseline = latest;
      _draft = latest;
    } else {
      _draft = _mergeExternal(_draft, latest);
      _baseline = latest;
    }
    _ensureRoot();
    notifyListeners();
    return true;
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

  /// Applies a full tree (used by tests and the "all tags" view).
  void applyFromWeb(Object? value) => applyTree(TagTree.fromJson(value));

  void applyTree(TagTree tree) {
    if (!tree.isVirtualRoot) {
      throw const FormatException('标签导图缺少根节点。');
    }
    final resolved = tree.mapIds(_assignedIds);
    if (resolved.sameAs(_draft)) return;
    _draft = resolved;
    _ensureRoot();
    notifyListeners();
  }

  /// Applies the subtree reported by the web view without touching tags
  /// outside the current root.
  void applyViewTree(TagTree tree) {
    final id = _stableId(_rootId);
    if (id == null) {
      applyTree(tree);
      return;
    }
    _rootId = id;
    final resolved = tree.mapIds(_assignedIds);
    if (resolved.isVirtualRoot || resolved.root.id != id) {
      throw const FormatException('导图根标签与当前视图不一致。');
    }
    final updated = _draft.replaceSubtree(resolved);
    if (updated.sameAs(_draft)) return;
    _draft = updated;
    notifyListeners();
  }

  /// Why [id] cannot be deleted, or null when deletion is allowed. The store
  /// repeats these checks before writing; this keeps the UI understandable.
  String? deleteBlocker(String id) {
    final stable = _stableId(id) ?? id;
    if (stable == tagTreeRootId) return '虚拟根节点不能删除。';
    if (stable == _rootId) return '当前根标签不能删除，请先切换根标签。';
    final node = this.node(stable);
    if (node == null) return '标签不存在。';
    if (node.children.isNotEmpty) return '请先删除或移动它的子标签。';
    final count =
        journal.store.events.values
            .where((event) => event.tagId == stable)
            .length +
        journal.drafts.values.where((event) => event.tagId == stable).length;
    if (count > 0) return '此标签还有 $count 个事件，请先给这些事件更换标签。';
    return null;
  }

  Future<TagTree> save() async {
    if (_saving) throw const FormatException('正在保存标签，请稍候。');
    if (!dirty) return _draft;
    _saving = true;
    notifyListeners();
    try {
      // Never overwrite tags that were added outside this page while a draft
      // was pending. Merge them first so a subtree save cannot erase them.
      final latest = TagTree.fromTags(journal.store.tags.values);
      if (!latest.sameAs(_baseline)) {
        _draft = _mergeExternal(_draft, latest);
        _baseline = latest;
        _ensureRoot();
      }
      final saving = _draft;
      final plan = saving.toTagMap(journal.store.tags);
      await journal.store.replaceTags(plan.tags);
      _assignedIds.addAll(plan.assignedIds);
      final saved = TagTree.fromTags(journal.store.tags.values);
      _baseline = saved;
      // Keep edits made while the write was in flight; their temporary ids
      // now resolve to the stable ids that were just persisted.
      _draft = _draft.sameAs(saving) ? saved : _draft.mapIds(plan.assignedIds);
      _rootId = _stableId(_rootId);
      _ensureRoot();
      journal.notifyListeners();
      return saved;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
