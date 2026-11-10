import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../domain/settings.dart';
import '../domain/obsidian.dart';
import 'dialogs.dart' show errorText;
import 'obsidian_sync_error.dart';

Future<void> showSettingsDialog(
  BuildContext context, {
  required AppSettings settings,
  required Future<void> Function(AppSettings) onSave,
  Future<int> Function(String)? onSyncObsidian,
  bool allowHistoryEditing = false,
  ValueChanged<bool>? onHistoryEditingChanged,
  Future<void> Function()? onOrganizeEvents,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SettingsDialog(
    settings: settings,
    onSave: onSave,
    onSyncObsidian: onSyncObsidian,
    allowHistoryEditing: allowHistoryEditing,
    onHistoryEditingChanged: onHistoryEditingChanged,
    onOrganizeEvents: onOrganizeEvents,
  ),
);

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.settings,
    required this.onSave,
    this.onSyncObsidian,
    required this.allowHistoryEditing,
    this.onHistoryEditingChanged,
    this.onOrganizeEvents,
  });
  final AppSettings settings;
  final Future<void> Function(AppSettings) onSave;
  final Future<int> Function(String)? onSyncObsidian;
  final bool allowHistoryEditing;
  final ValueChanged<bool>? onHistoryEditingChanged;
  final Future<void> Function()? onOrganizeEvents;
  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late bool _autoUndefined = widget.settings.autoUndefined;
  late int _dragMinutes = widget.settings.dragMinutes;
  late bool _splitOverlap = widget.settings.splitOverlap;
  late bool _allowHistoryEditing = widget.allowHistoryEditing;
  late final _obsidian = TextEditingController(
    text: widget.settings.obsidianDirectory,
  );
  String? _syncMessage;
  bool _saving = false;

  @override
  void dispose() {
    _obsidian.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    try {
      final path = await getDirectoryPath(
        initialDirectory: _obsidian.text.trim().isEmpty
            ? null
            : _obsidian.text.trim(),
        confirmButtonText: '选择事项文件夹',
      );
      if (mounted && path != null) setState(() => _obsidian.text = path);
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    }
  }

  Future<void> _sync() async {
    setState(() {
      _saving = true;
      _error = null;
      _syncMessage = null;
    });
    try {
      final count = await widget.onSyncObsidian!(_obsidian.text.trim());
      if (mounted) setState(() => _syncMessage = '已同步 $count 个事项');
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
      if (mounted && error is ObsidianDuplicateIdException) {
        await showObsidianDuplicateError(context, error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _error;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        AppSettings(
          autoUndefined: _autoUndefined,
          dragMinutes: _dragMinutes,
          splitOverlap: _splitOverlap,
          obsidianDirectory: _obsidian.text.trim(),
        ),
      );
      widget.onHistoryEditingChanged?.call(_allowHistoryEditing);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return AlertDialog(
      title: const Text('设置'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.onOrganizeEvents != null) ...[
                ListTile(
                  key: const ValueKey('organize-events'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.drive_file_move_outline),
                  title: const Text('历史事件整理', style: TextStyle(fontSize: 16)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _saving ? null : widget.onOrganizeEvents,
                ),
                const Divider(height: 24),
              ],
              Text('时间记录', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              SwitchListTile(
                key: const ValueKey('setting-auto-undefined'),
                contentPadding: EdgeInsets.zero,
                title: const Text('自动生成空档'),
                subtitle: const Text(
                  '自动补全事件之间的空档；可在时间轴的「显示」菜单中折叠。关闭后不再生成或显示，已有名称和备注保留，重新开启后恢复。',
                ),
                value: _autoUndefined,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _autoUndefined = value),
              ),
              const Divider(height: 24),
              SwitchListTile(
                key: const ValueKey('setting-history-editing'),
                contentPadding: EdgeInsets.zero,
                title: const Text('允许修改已归档事件'),
                subtitle: const Text('仅本次运行有效，重新打开软件后自动关闭。关闭时已归档事件仅可修改标签。'),
                value: _allowHistoryEditing,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _allowHistoryEditing = value),
              ),
              const Divider(height: 24),
              Text('拖动颗粒度', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text('在时间轴上拖动事件或调整起止时间时使用的时间单位。', style: hint),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final minutes in dragGranularities)
                    ChoiceChip(
                      key: ValueKey('granularity-$minutes'),
                      label: Text(dragGranularityText(minutes)),
                      selected: _dragMinutes == minutes,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _dragMinutes = minutes),
                    ),
                ],
              ),
              const Divider(height: 24),
              Text('统计口径', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              SwitchListTile(
                key: const ValueKey('setting-split-overlap'),
                contentPadding: EdgeInsets.zero,
                title: const Text('并行时段平均分摊'),
                subtitle: const Text(
                  '同时进行的多个事件平均分配重叠的时间：8:00–12:00 内 4 件并行事件各计 1 小时。关闭后每个标签仍按整段时间完整计入。',
                ),
                value: _splitOverlap,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _splitOverlap = value),
              ),
              const Divider(height: 24),
              Text(
                'Obsidian 事项',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('setting-obsidian-directory'),
                controller: _obsidian,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: '事项文件夹',
                  hintText: r'E:\Data\Documents\Vault\Daymark',
                  suffixIcon: IconButton(
                    key: const ValueKey('browse-obsidian-directory'),
                    tooltip: '选择文件夹',
                    onPressed: _saving ? null : _browse,
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '读取此文件夹中的 Markdown。启动时自动同步，也可立即同步；子事项继承标签，缺失标签自动创建。',
                style: hint,
              ),
              if (widget.onSyncObsidian != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('sync-obsidian'),
                    onPressed: _saving ? null : _sync,
                    icon: const Icon(Icons.sync),
                    label: const Text('立即同步'),
                  ),
                ),
              if (_syncMessage != null) Text(_syncMessage!, style: hint),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('save-settings'),
          onPressed: _saving ? null : _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
