// Snaps off-scale UI values onto the token scale, across the whole codebase.
//
//   dart run tool/snap_to_tokens.dart --dry    # report what would change
//   dart run tool/snap_to_tokens.dart          # write the changes
//
// This is the mechanical 80% of removing the generated look: 13.5 becomes 14,
// a 7px gap becomes 8, an 11px radius becomes 12. None of those individually
// matters; all of them together are what the eye reads as "off".
//
// What it deliberately will NOT touch, because these need judgement:
//   - spacing above 48, which is nearly always a fixed dimension (an avatar,
//     a chart height, a reserved gap) rather than a gap on the scale
//   - inline Color(0x…) literals, where the right answer is which token it
//     should have been, not which hex is nearest
//   - anything in the theme files, which are the scale's definition

import 'dart:io';

const _exempt = <String>[
  'lib/core/theme/tokens.dart',
  'lib/core/theme/app_colors.dart',
  'lib/core/theme/app_theme.dart',
  'lib/core/theme/app_spacing.dart',
  'lib/core/theme/app_depth.dart',
];

/// Spacing steps. Values above the top of this list are left alone.
const _grid = <int>[0, 4, 8, 12, 16, 20, 24, 32, 40, 48];

/// Type sizes, mapped by band rather than nearest so a 26px figure lands on
/// the display size instead of being pulled down to a heading.
double _snapType(double v) {
  if (v < 13) return 12;
  if (v <= 15) return 14;
  if (v <= 18) return 16;
  if (v <= 23) return 20;
  return 32;
}

int _snapGrid(double v) {
  var best = _grid.first;
  var bestD = (v - best).abs();
  for (final g in _grid) {
    final d = (v - g).abs();
    if (d < bestD) {
      best = g;
      bestD = d;
    }
  }
  return best;
}

double _snapRadius(double v) {
  if (v >= 100) return v; // full-round, leave it
  if (v < 14) return 12;
  if (v <= 18) return 16;
  return 20;
}

String _fmt(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

void main(List<String> args) {
  final dry = args.contains('--dry');
  final root = Directory('lib');
  if (!root.existsSync()) {
    stderr.writeln('run me from the mobile/ directory');
    exit(2);
  }

  var files = 0, type = 0, spacing = 0, radius = 0;

  for (final e in root.listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final rel = e.path.replaceAll(r'\', '/');
    if (_exempt.any(rel.endsWith)) continue;
    if (rel.endsWith('.g.dart') || rel.contains('/l10n/gen/')) continue;

    final src = e.readAsStringSync();
    var out = src;

    out = out.replaceAllMapped(
      RegExp(r'fontSize:\s*([0-9]+(?:\.[0-9]+)?)'),
      (m) {
        final v = double.parse(m[1]!);
        final s = _snapType(v);
        if (s == v) return m[0]!;
        type++;
        return 'fontSize: ${_fmt(s)}';
      },
    );

    out = out.replaceAllMapped(
      RegExp(
        r'(EdgeInsets\.(?:all|symmetric|only|fromLTRB)\(|'
        r'SizedBox\(\s*(?:width|height):\s*|'
        r'(?:horizontal|vertical|left|top|right|bottom|spacing|runSpacing):\s*)'
        r'([0-9]+(?:\.[0-9]+)?)',
      ),
      (m) {
        final v = double.parse(m[2]!);
        if (v > 48) return m[0]!; // a dimension, not a gap
        final s = _snapGrid(v);
        if (s == v) return m[0]!;
        spacing++;
        return '${m[1]}$s';
      },
    );

    out = out.replaceAllMapped(
      RegExp(r'Radius\.circular\(\s*([0-9]+(?:\.[0-9]+)?)'),
      (m) {
        final v = double.parse(m[1]!);
        final s = _snapRadius(v);
        if (s == v) return m[0]!;
        radius++;
        return 'Radius.circular(${_fmt(s)}';
      },
    );

    if (out != src) {
      files++;
      if (!dry) e.writeAsStringSync(out);
    }
  }

  final verb = dry ? 'would change' : 'changed';
  stdout.writeln(
    '$verb $files files — $type type · $spacing spacing · $radius radius',
  );
}
