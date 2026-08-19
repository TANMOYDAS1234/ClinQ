import 'package:flutter/material.dart';

/// A deliberately small Markdown renderer for assistant replies.
///
/// The model returns lightweight Markdown — `**bold**` for key terms and `- `
/// bullets for steps. Rendering it as plain text showed the literal `**` and
/// `*`, which reads as broken. A full Markdown package is far more than a chat
/// bubble needs (and drags in styling that fights the app theme), so this
/// handles exactly what the model produces: paragraphs, `-`/`*`/`•` bullets,
/// and inline `**bold**` / `*italic*`.
class MarkdownText extends StatelessWidget {
  const MarkdownText({
    super.key,
    required this.data,
    required this.style,
    this.bulletColor,
    this.selectable = false,
  });

  final String data;
  final TextStyle style;
  final Color? bulletColor;

  /// When true, each paragraph and bullet is a [SelectableText], so the patient
  /// can long-press to select a word and copy it — using the platform's own
  /// selection handles, which render correctly for Bengali and Devanagari.
  final bool selectable;

  /// Strips the Markdown marks so copied/selected text — and message previews —
  /// read as clean prose, not literal `**`, `#`, `` ` `` or `- `.
  static String toPlainText(String data) => data
      // Bold, then italic (italic's look-behind keeps it off the ** it leaves).
      .replaceAllMapped(RegExp(r'(\*\*|__)(.+?)\1'), (m) => m.group(2)!)
      .replaceAllMapped(RegExp(r'(?<!\*)(\*|_)(?!\s)(.+?)\1'), (m) => m.group(2)!)
      .replaceAllMapped(RegExp(r'~~(.+?)~~'), (m) => m.group(1)!)
      .replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1)!)
      // [text](url) -> text
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1)!)
      // Leading #, >, and heading/quote marks.
      .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ')
      .trim();

  /// [toPlainText] collapsed to a single line — for list previews, where a
  /// message's line breaks would otherwise stack up two ragged lines.
  static String toPreview(String data) => toPlainText(data).replaceAll(RegExp(r'\s+'), ' ').trim();

  static final _bullet = RegExp(r'^\s*[-*•]\s+(.*)$');
  // Bold first (**x** / __x__), then italic (*x* / _x_).
  static final _inline = RegExp(r'(\*\*|__)(.+?)\1|(\*|_)(.+?)\3');

  List<InlineSpan> _spans(String text) {
    final spans = <InlineSpan>[];
    var index = 0;
    for (final m in _inline.allMatches(text)) {
      if (m.start > index) spans.add(TextSpan(text: text.substring(index, m.start)));
      if (m.group(2) != null) {
        spans.add(TextSpan(text: m.group(2), style: const TextStyle(fontWeight: FontWeight.w700)));
      } else {
        spans.add(TextSpan(text: m.group(4), style: const TextStyle(fontStyle: FontStyle.italic)));
      }
      index = m.end;
    }
    if (index < text.length) spans.add(TextSpan(text: text.substring(index)));
    return spans;
  }

  Widget _line(TextSpan span) => selectable
      ? SelectableText.rich(span)
      : Text.rich(span);

  @override
  Widget build(BuildContext context) {
    // Collapse the runs of blank lines the model sometimes emits, so paragraph
    // gaps stay even.
    final lines = data.replaceAll(RegExp(r'\n{3,}'), '\n\n').split('\n');
    final children = <Widget>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        // Blank line = paragraph gap, but don't stack gaps or lead with one.
        if (children.isNotEmpty) children.add(const SizedBox(height: 8));
        continue;
      }

      final bullet = _bullet.firstMatch(line);
      if (bullet != null) {
        children.add(
          Padding(
            padding: EdgeInsets.only(top: children.isEmpty ? 0 : 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 0, right: 8),
                  child: Text('•', style: style.copyWith(color: bulletColor ?? style.color)),
                ),
                Expanded(
                  child: _line(TextSpan(style: style, children: _spans(bullet.group(1)!))),
                ),
              ],
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: EdgeInsets.only(top: children.isEmpty ? 0 : 2),
            child: _line(TextSpan(style: style, children: _spans(line))),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
