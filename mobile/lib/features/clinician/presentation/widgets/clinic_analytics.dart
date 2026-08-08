import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../domain/clinician_models.dart';
import 'sparkline.dart';

/// The population charts for the doctor's home — clinic-wide aggregates, never
/// 100 patient lines. Three cards: how the whole clinic's control is trending,
/// how risk is distributed, and who to look at first.

// ---------------------------------------------------------------------------
// Shared card chrome
// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.title, this.subtitle, required this.child});

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = AppColors.accentOn(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(subtitle!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

Widget _emptyHint(BuildContext context, String text) {
  final scheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Row(
      children: [
        Icon(Icons.insights_rounded, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, height: 1.35, color: scheme.onSurfaceVariant))),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// 1. Clinic glucose-control trend (100% stacked area: low / in-range / high)
// ---------------------------------------------------------------------------

class ClinicControlTrendCard extends StatelessWidget {
  const ClinicControlTrendCard({super.key, required this.analytics});

  final ClinicAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A refined, lower-saturation palette for the chart itself — the status
    // colours read as an alarm; these read as an analytic.
    const inRange = Color(0xFF2FBF87); // calm emerald — the hero band
    const high = Color(0xFFE7A13D); // warm amber, not alarm-orange
    const low = Color(0xFFDE7A76); // soft rose

    // Only days that actually have readings; a no-reading day carries no
    // proportion and would otherwise read as "all high".
    final pts = analytics.controlTrend.where((p) => p.total > 0).toList();

    // Don't draw a trend from a handful of readings — a jumpy line off 5 points
    // reads as signal when it's noise.
    final tooThin = pts.length < 3 || analytics.totalReadings < 15;

    final subtitle = analytics.totalReadings == 0
        ? null
        : '${analytics.totalReadings} readings · last ${analytics.controlTrend.length} days';

    // Window averages for the hero figure and the mini stats.
    var sumLow = 0, sumIn = 0, sumHigh = 0, sumTot = 0;
    for (final p in pts) {
      sumLow += p.low;
      sumIn += p.inRange;
      sumHigh += p.high;
      sumTot += p.total;
    }
    int pct(int n) => sumTot == 0 ? 0 : (n / sumTot * 100).round();

    return _Card(
      icon: Icons.insights_rounded,
      title: 'Clinic glucose control',
      subtitle: subtitle,
      child: tooThin
          ? _emptyHint(context, 'Not enough readings yet — the clinic trend fills in as patients check in.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero: the one figure a doctor scans for — clinic-wide time in range.
                Row(
                  children: [
                    Text('${pct(sumIn)}%',
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1, color: inRange)),
                    const SizedBox(width: 7),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('in range', style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
                    ),
                    const Spacer(),
                    _MiniPct(label: 'High', value: pct(sumHigh), color: high),
                    const SizedBox(width: 8),
                    _MiniPct(label: 'Low', value: pct(sumLow), color: low),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(height: 172, child: _IsoBars(pts: pts, low: low, inRange: inRange, high: high)),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    _LegendDot(color: inRange, label: 'In range'),
                    _LegendDot(color: high, label: 'High'),
                    _LegendDot(color: low, label: 'Low'),
                  ],
                ),
                // Is monitoring actually happening? Distinct patients logging
                // each day — a flat-low line means the clinic isn't checking in.
                if (analytics.engagement.length >= 2) ...[
                  const SizedBox(height: AppSpacing.md),
                  Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Icon(Icons.how_to_reg_rounded, size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Patients checking in / day',
                            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                      ),
                      Sparkline(
                        values: [for (final e in analytics.engagement) e.patients.toDouble()],
                        color: AppColors.accentOn(context),
                        width: 84,
                        height: 22,
                        showBand: false,
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

/// A compact "18% High" pill for the control-trend hero row.
class _MiniPct extends StatelessWidget {
  const _MiniPct({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$value%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11.5, color: color.withValues(alpha: 0.95))),
        ],
      ),
    );
  }
}

/// The clinic control trend as isometric 3D bars — one column per day (bucketed
/// when the window is long), each a full-height stack of low / in-range / high
/// proportions, extruded with darker side faces and lighter top faces for depth.
class _IsoBars extends StatelessWidget {
  const _IsoBars({required this.pts, required this.low, required this.inRange, required this.high});

  final List<ControlPoint> pts;
  final Color low;
  final Color inRange;
  final Color high;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _IsoBarsPainter(
        bars: _bucket(pts, 12),
        low: low,
        inRange: inRange,
        high: high,
        grid: scheme.outlineVariant.withValues(alpha: 0.30),
        axis: scheme.onSurfaceVariant,
      ),
      child: const SizedBox.expand(),
    );
  }

  /// Keep the columns chunky and legible: fold a long day-by-day window into at
  /// most [maxBars] buckets, summing counts so the proportions stay honest.
  static List<ControlPoint> _bucket(List<ControlPoint> pts, int maxBars) {
    if (pts.length <= maxBars) return pts;
    final size = (pts.length / maxBars).ceil();
    final out = <ControlPoint>[];
    for (var i = 0; i < pts.length; i += size) {
      final end = (i + size) < pts.length ? i + size : pts.length;
      var l = 0, r = 0, h = 0, t = 0;
      for (var j = i; j < end; j++) {
        l += pts[j].low;
        r += pts[j].inRange;
        h += pts[j].high;
        t += pts[j].total;
      }
      out.add(ControlPoint(date: pts[(i + end - 1) ~/ 2].date, low: l, inRange: r, high: h, total: t));
    }
    return out;
  }
}

class _IsoBarsPainter extends CustomPainter {
  _IsoBarsPainter({
    required this.bars,
    required this.low,
    required this.inRange,
    required this.high,
    required this.grid,
    required this.axis,
  });

  final List<ControlPoint> bars;
  final Color low;
  final Color inRange;
  final Color high;
  final Color grid;
  final Color axis;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    const padL = 30.0, padTBase = 12.0, padB = 20.0, depMax = 15.0;
    const padR = depMax + 6;
    final chartW = size.width - padL - padR;
    if (chartW <= 0) return;

    final n = bars.length;
    final slotW = chartW / n;
    final barW = (slotW * 0.6).clamp(6.0, 42.0);
    final gap = slotW - barW;
    final dep = [barW * 0.5, gap * 0.9, depMax].reduce((a, b) => a < b ? a : b);
    final depX = dep, depY = dep * 0.52;
    final padT = padTBase + depY;
    final chartH = size.height - padT - padB;
    if (chartH <= 0) return;
    final baseY = padT + chartH;
    double y(double p) => baseY - p * chartH;

    // Faint reference grid + left % axis.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.6;
    for (final p in const [0.0, 0.25, 0.5, 0.75, 1.0]) {
      canvas.drawLine(Offset(padL, y(p)), Offset(padL + chartW, y(p)), gridPaint);
    }
    for (final p in const [0.0, 0.5, 1.0]) {
      _label(canvas, '${(p * 100).round()}%', Offset(padL - 5, y(p)), anchorRight: true, vCenter: true);
    }

    Color side(Color c) => Color.lerp(c, Colors.black, 0.34)!;
    Color topFace(Color c) => Color.lerp(c, Colors.white, 0.30)!;

    for (var i = 0; i < n; i++) {
      final b = bars[i];
      if (b.total <= 0) continue;
      final l = padL + i * slotW + (slotW - barW) / 2;
      final r = l + barW;
      final lf = b.low / b.total, inf = b.inRange / b.total, hf = b.high / b.total;
      final segs = <(double, double, Color)>[
        (0.0, lf, low),
        (lf, lf + inf, inRange),
        (lf + inf, 1.0, high),
      ];
      final topColor = hf > 0 ? high : (inf > 0 ? inRange : low);

      // Right side faces (darker) — the depth of the column.
      for (final s in segs) {
        if (s.$2 - s.$1 <= 0.0001) continue;
        final p = Path()
          ..moveTo(r, y(s.$2))
          ..lineTo(r + depX, y(s.$2) - depY)
          ..lineTo(r + depX, y(s.$1) - depY)
          ..lineTo(r, y(s.$1))
          ..close();
        canvas.drawPath(p, Paint()..color = side(s.$3));
      }
      // Single top face (lighter) at the column's ceiling.
      final topP = Path()
        ..moveTo(l, y(1.0))
        ..lineTo(r, y(1.0))
        ..lineTo(r + depX, y(1.0) - depY)
        ..lineTo(l + depX, y(1.0) - depY)
        ..close();
      canvas.drawPath(topP, Paint()..color = topFace(topColor));
      // Front faces, with a subtle top-lit gradient for a glossy 3D read.
      for (final s in segs) {
        if (s.$2 - s.$1 <= 0.0001) continue;
        final rect = Rect.fromLTRB(l, y(s.$2), r, y(s.$1));
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(s.$3, Colors.white, 0.14)!, s.$3],
            ).createShader(rect),
        );
      }
    }

    // A few date labels along the bottom.
    final step = (n / 4).ceil().clamp(1, n);
    for (var i = 0; i < n; i += step) {
      final l = padL + i * slotW + (slotW - barW) / 2;
      _label(canvas, DateFormat('d/M').format(bars[i].date), Offset(l + barW / 2, baseY + 5), hCenter: true);
    }
  }

  void _label(Canvas canvas, String text, Offset at,
      {bool anchorRight = false, bool hCenter = false, bool vCenter = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: axis, fontSize: 9.5)),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (anchorRight) dx = at.dx - tp.width;
    if (hCenter) dx = at.dx - tp.width / 2;
    var dy = at.dy;
    if (vCenter) dy = at.dy - tp.height / 2;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_IsoBarsPainter old) =>
      old.bars != bars || old.low != low || old.inRange != inRange || old.high != high;
}

// ---------------------------------------------------------------------------
// 2. Risk distribution donut
// ---------------------------------------------------------------------------

class RiskDonutCard extends StatelessWidget {
  const RiskDonutCard({super.key, required this.overview});

  final ClinicOverview overview;

  @override
  Widget build(BuildContext context) {
    final low = AppColors.successOn(context);
    final moderate = AppColors.warningOn(context);
    final high = const Color(0xFFF97316); // orange, between warning and danger
    final critical = AppColors.dangerOn(context);

    final segments = <(String, int, Color)>[
      ('Low', overview.riskLow, low),
      ('Moderate', overview.riskModerate, moderate),
      ('High', overview.riskHigh, high),
      ('Critical', overview.riskCritical, critical),
    ];
    final total = segments.fold(0, (s, e) => s + e.$2);

    return _Card(
      icon: Icons.donut_large_rounded,
      title: 'Risk distribution',
      subtitle: total > 0 ? '$total patients' : null,
      child: total == 0
          ? _emptyHint(context, 'No risk data yet.')
          : Row(
              children: [
                SizedBox(
                  width: 118,
                  height: 118,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 34,
                          startDegreeOffset: -90,
                          sections: [
                            for (final s in segments)
                              if (s.$2 > 0)
                                PieChartSectionData(
                                  value: s.$2.toDouble(),
                                  color: s.$3,
                                  radius: 22,
                                  showTitle: false,
                                ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$total', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1)),
                          Text('patients', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final s in segments)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              _dot(s.$3),
                              const SizedBox(width: 8),
                              Expanded(child: Text(s.$1, style: const TextStyle(fontSize: 13.5))),
                              Text('${s.$2}',
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _dot(Color c) => Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

// ---------------------------------------------------------------------------
// 3. Top-N "needs attention" with sparklines
// ---------------------------------------------------------------------------

class AttentionListCard extends StatelessWidget {
  const AttentionListCard({super.key, required this.patients, this.max = 6});

  final List<PatientListItem> patients;
  final int max;

  @override
  Widget build(BuildContext context) {
    // Rank: open alerts first, then risk score, then most overdue.
    final ranked = [...patients]..sort((a, b) {
        final alert = b.openAlertCount.compareTo(a.openAlertCount);
        if (alert != 0) return alert;
        final risk = b.riskScore.compareTo(a.riskScore);
        if (risk != 0) return risk;
        return (b.checkInOverdue ? 1 : 0).compareTo(a.checkInOverdue ? 1 : 0);
      });
    final top = ranked.take(max).toList();

    return _Card(
      icon: Icons.priority_high_rounded,
      title: 'Needs attention',
      subtitle: top.isEmpty ? null : 'Highest-priority patients first',
      child: top.isEmpty
          ? _emptyHint(context, 'No patients flagged right now.')
          : Column(
              children: [
                for (var i = 0; i < top.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  _AttentionRow(patient: top[i]),
                ],
              ],
            ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.patient});

  final PatientListItem patient;

  String _ago(DateTime at) {
    final d = DateTime.now().difference(at).inDays;
    if (d <= 0) return 'today';
    if (d == 1) return '1d';
    if (d < 21) return '${d}d';
    return '${(d / 7).round()}w';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final riskColor = switch (patient.riskBand) {
      'critical' => AppColors.dangerOn(context),
      'high' => const Color(0xFFF97316),
      'moderate' => AppColors.warningOn(context),
      _ => AppColors.successOn(context),
    };

    return InkWell(
      onTap: () => context.push('/clinician/patients/${patient.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            UserAvatar(name: patient.name, avatarUrl: patient.avatarUrl, accent: riskColor, size: 38),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(patient.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  // Wrap, not Row: the risk chip + alerts + recency must never
                  // clip on a narrow phone; they flow to a second line instead.
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: riskColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
                        child: Text(patient.riskBand,
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: riskColor)),
                      ),
                      if (patient.openAlertCount > 0)
                        Text('${patient.openAlertCount} alert${patient.openAlertCount == 1 ? '' : 's'}',
                            style: TextStyle(fontSize: 11.5, color: AppColors.dangerOn(context), fontWeight: FontWeight.w600)),
                      if (patient.lastReadingAt != null)
                        Text('· ${_ago(patient.lastReadingAt!)}',
                            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (patient.spark.length >= 2)
              Sparkline(values: patient.spark, color: AppColors.accentOn(context), width: 56, height: 22),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 11, height: 11, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
