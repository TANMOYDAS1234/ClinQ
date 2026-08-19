import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// The band that gives a patient screen a subject.
///
/// Every screen in this panel was a stack of cards of equal weight — a correct
/// layout and a boring one, because nothing dominates and so the eye has
/// nowhere to land. This is the fix, and it is one component rather than three
/// so the tabs cannot drift apart: same gradient, same rhythm, same figure size
/// on Home, Medicines and Profile.
///
/// Light rather than a dark band, deliberately. Colour has to own real area for
/// a screen to feel designed, but large light-on-dark text produces halation
/// for exactly the retinopathy this app exists to manage — so the ground is
/// tinted and the type stays dark.
class HeroBand extends StatelessWidget {
  const HeroBand({
    super.key,
    required this.eyebrow,
    required this.title,
    this.trailing,
    this.figure,
    this.footer,
    this.child,
  });

  /// The small line above the title — a greeting, a date, a role.
  final String eyebrow;

  /// The screen's name, or the person's.
  final String title;

  /// Sits opposite the title: a risk badge, an avatar.
  final Widget? trailing;

  /// The screen's subject, if it has a single number.
  final HeroFigure? figure;

  /// Runs under the figure — a sparkline, a progress bar.
  final Widget? footer;

  /// Shown instead of [figure] when there is no number yet.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return HeroSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 32,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ],
            ],
          ),
          if (figure != null || child != null) ...[
            const SizedBox(height: AppSpacing.lg),
            if (figure != null) figure! else child!,
          ],
          if (footer != null) ...[
            const SizedBox(height: AppSpacing.md),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// The tinted ground the bands sit on, on its own so a screen whose hero is
/// not a number — Profile, whose subject is a face — can use the same colour
/// without pretending to have a figure.
class HeroSurface extends StatelessWidget {
  const HeroSurface({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding:
          padding ??
          const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.lg,
          ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.14),
            AppColors.accent.withValues(alpha: 0.10),
            scheme.surface,
          ],
          stops: const [0, 0.55, 1],
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppSpacing.sheetRadius),
        ),
      ),
      child: child,
    );
  }
}

/// The screen's subject: one number, its unit, what it means, and when.
class HeroFigure extends StatelessWidget {
  const HeroFigure({
    super.key,
    required this.value,
    this.unit,
    this.caption,
    this.statusLabel,
    this.statusColor,
  });

  final String value;
  final String? unit;
  final String? caption;
  final String? statusLabel;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = statusColor ?? AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // The figure and its unit take every pixel the status pill does
            // not. This was a Flexible followed by a Spacer, and both of those
            // take flex — so the Spacer claimed half the free width and a
            // four-character figure ellipsised to "7…". Grouping the figure
            // with its unit inside one Expanded, and letting the pill size
            // itself, is what actually reserves the space correctly.
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        // Deliberately off the type scale, and the only place in the
                        // app that is: this is the screen's subject, and a subject
                        // one step larger than a heading does not read as one. The
                        // token checker exempts it by name rather than by accident.
                        fontSize: 64,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -3,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  if (unit != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        unit!,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (statusLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(
                      AppSpacing.buttonRadius,
                    ),
                    border: Border.all(color: tone.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    statusLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tone,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (caption != null) ...[
          const SizedBox(height: 4),
          Text(
            caption!,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// A trend line for the band's footer. Unlabelled on purpose — the numbers live
/// in the cards below; this only has to say "rising" or "settling".
class HeroSpark extends StatelessWidget {
  const HeroSpark({super.key, required this.values, this.height = 40});

  final List<double> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _SparkPainter(values, AppColors.primary),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter(this.values, this.tone);

  final List<double> values;
  final Color tone;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final span = (hi - lo).abs() < 0.001 ? 1.0 : hi - lo;

    Offset at(int i) => Offset(
      i * size.width / (values.length - 1),
      size.height - 4 - (values[i] - lo) / span * (size.height - 8),
    );

    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }

    canvas.drawPath(
      Path.from(line)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tone.withValues(alpha: 0.22), tone.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = tone.withValues(alpha: 0.85),
    );

    final head = at(values.length - 1);
    canvas.drawCircle(head, 4, Paint()..color = tone);
    canvas.drawCircle(
      head,
      4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.tone != tone;
}

/// A flat progress bar for the band's footer, where the subject is a
/// proportion rather than a trend — doses taken, tests completed.
class HeroProgress extends StatelessWidget {
  const HeroProgress({
    super.key,
    required this.fraction,
    required this.label,
    this.tone,
  });

  final double fraction;
  final String label;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = tone ?? AppColors.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: c.withValues(alpha: 0.14),
            valueColor: AlwaysStoppedAnimation(c),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
