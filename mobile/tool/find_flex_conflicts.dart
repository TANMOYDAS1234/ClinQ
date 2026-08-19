// Finds Rows and Columns where a Spacer competes with a Flexible/Expanded.
//
//   dart run tool/find_flex_conflicts.dart
//
// Both Spacer and Flexible take flex, so they SPLIT the free space. When the
// flexible child is text, it gets half the room it should have and ellipsises
// early — a 4-character figure rendering as "7…" beside a half-empty gap.
//
// This is not always a bug: two flexible children deliberately sharing space is
// a legitimate layout. It is a bug when one of them is content that must not be
// truncated and the other is a Spacer whose only job is to push. So this
// reports rather than rewrites; each hit needs a human decision.
//
// One shape is a known false positive and is left in rather than special-cased,
// because recognising it needs real parsing:
//
//   if (x) Expanded(...) else const Spacer()
//
// Both appear in the source, only one is ever built, and there is no conflict.
// Check the branch before changing anything.

import 'dart:io';

/// The balanced region starting at the '(' that follows [from].
({int start, int end})? _balanced(String s, int from) {
  final open = s.indexOf('(', from);
  if (open < 0) return null;
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    final c = s[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return (start: open, end: i);
    }
  }
  return null;
}

/// Direct children of a `children: [ ... ]` list inside [body], ignoring any
/// nested lists — a Spacer three widgets deep is not competing with this Row.
String? _directChildren(String body) {
  final key = body.indexOf('children:');
  if (key < 0) return null;
  final open = body.indexOf('[', key);
  if (open < 0) return null;
  var depth = 0;
  for (var i = open; i < body.length; i++) {
    final c = body[i];
    if (c == '[') depth++;
    if (c == ']') {
      depth--;
      if (depth == 0) return body.substring(open + 1, i);
    }
  }
  return null;
}

/// Strips anything nested inside a child, so `Expanded(child: Row(... Spacer))`
/// does not read as this Row holding a Spacer.
String _topLevelOnly(String children) {
  final out = StringBuffer();
  var paren = 0, square = 0;
  for (final c in children.split('')) {
    if (c == '(') paren++;
    if (c == '[') square++;
    if (paren == 0 && square == 0) out.write(c);
    if (c == ')') paren--;
    if (c == ']') square--;
    // Keep the widget name that opens each child.
    if (paren == 1 && c == '(') out.write('(');
  }
  return out.toString();
}

void main() {
  final root = Directory('lib');
  var hits = 0, files = 0;

  for (final e in root.listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final rel = e.path.replaceAll(r'\', '/');
    final src = e.readAsStringSync();
    final found = <String>[];

    for (final m in RegExp(r'\b(Row|Column)\(').allMatches(src)) {
      final region = _balanced(src, m.start);
      if (region == null) continue;
      final body = src.substring(region.start, region.end);
      final children = _directChildren(body);
      if (children == null) continue;
      final top = _topLevelOnly(children);

      final hasSpacer = RegExp(r'\bSpacer\(').hasMatch(top);
      final hasFlex = RegExp(r'\b(Expanded|Flexible)\(').hasMatch(top);
      if (hasSpacer && hasFlex) {
        final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        found.add('  $line: ${m.group(1)} — Spacer beside Expanded/Flexible');
      }
    }

    if (found.isNotEmpty) {
      files++;
      hits += found.length;
      stdout.writeln('\n$rel');
      for (final f in found) {
        stdout.writeln(f);
      }
    }
  }

  stdout.writeln(
    '\n$hits site${hits == 1 ? '' : 's'} across $files file${files == 1 ? '' : 's'}',
  );
}
