import 'package:flutter/material.dart';

import '../domain/settings.dart';
import 'dialogs.dart' show errorText;

Future<void> showSettingsDialog(
  BuildContext context, {
  required AppSettings settings,
  required Future<void> Function(AppSettings) onSave,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SettingsDialog(settings: settings, onSave: onSave),
);

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.settings, required this.onSave});
  final AppSettings settings;
  final Future<void> Function(AppSettings) onSave;
  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late bool _autoUndefined = widget.settings.autoUndefined;
  late int _dragMinutes = widget.settings.dragMinutes;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        AppSettings(autoUndefined: _autoUndefined, dragMinutes: _dragMinutes),
      );
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
              Text('时间记录', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              SwitchListTile(
                key: const ValueKey('setting-auto-undefined'),
                contentPadding: EdgeInsets.zero,
                title: const Text('自动生成未定义事件'),
                subtitle: const Text(
                  '在相邻事件之间的空档生成「未定义」记录。关闭后记录不再显示，但已填写的名称会保留，重新开启后恢复。',
                ),
                value: _autoUndefined,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _autoUndefined = value),
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
