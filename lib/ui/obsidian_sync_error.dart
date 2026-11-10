import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/obsidian.dart';

/// Keep source locations visible until the user has inspected or copied them.
Future<void> showObsidianDuplicateError(
  BuildContext context,
  ObsidianDuplicateIdException error,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    key: const ValueKey('obsidian-duplicate-dialog'),
    title: const Text('Obsidian 同 ID 事项冲突'),
    content: SizedBox(
      width: 640,
      child: SingleChildScrollView(child: SelectableText(error.message)),
    ),
    actions: [
      TextButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: error.message));
        },
        icon: const Icon(Icons.copy),
        label: const Text('复制详情'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭'),
      ),
    ],
  ),
);
