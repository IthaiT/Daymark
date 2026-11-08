import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/obsidian_navigation.dart';
import 'dialogs.dart' show errorText;

/// Selectable imported text, with Obsidian wikilinks rendered as real links.
class ObsidianText extends StatefulWidget {
  const ObsidianText({
    super.key,
    required this.text,
    required this.directory,
    required this.sourcePath,
    this.style,
    this.selectable = true,
    this.maxLines,
    this.openNote = openObsidianNote,
  });
  final String text;
  final String directory;
  final String sourcePath;
  final TextStyle? style;
  final bool selectable;
  final int? maxLines;
  final Future<void> Function(String, String) openNote;
  @override
  State<ObsidianText> createState() => _ObsidianTextState();
}

class _ObsidianTextState extends State<ObsidianText> {
  final _recognizers = <TapGestureRecognizer>[];
  void _clear() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  Future<void> _open(String target) async {
    try {
      if (target.startsWith('#')) target = '${widget.sourcePath}$target';
      await widget.openNote(widget.directory, target);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorText(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in RegExp(r'\[\[([^\]]+)\]\]').allMatches(widget.text)) {
      spans.add(TextSpan(text: widget.text.substring(start, match.start)));
      final target = match[1]!;
      final parts = target.split('|');
      final recognizer = TapGestureRecognizer()
        ..onTap = () => unawaited(_open(parts.first));
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: parts.length > 1 ? parts.last : parts.first,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: recognizer,
          mouseCursor: SystemMouseCursors.click,
        ),
      );
      start = match.end;
    }
    spans.add(TextSpan(text: widget.text.substring(start)));
    final text = TextSpan(children: spans);
    return widget.selectable
        ? SelectableText.rich(
            text,
            style: widget.style,
            maxLines: widget.maxLines,
          )
        : Text.rich(
            text,
            style: widget.style,
            maxLines: widget.maxLines,
            overflow: TextOverflow.ellipsis,
          );
  }
}
