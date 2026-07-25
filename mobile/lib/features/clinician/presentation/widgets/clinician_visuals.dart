import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Colour for a clinical-alert severity.
Color alertSeverityColor(String severity) => switch (severity) {
  'emergency' => AppColors.danger,
  'urgent' => AppColors.warning,
  'warning' => const Color(0xFFCA8A04),
  _ => AppColors.primary,
};

/// Colour for a patient risk band (doctor segmentation).
Color riskBandColor(String band) => switch (band) {
  'critical' => AppColors.danger,
  'high' => const Color(0xFFEA580C),
  'moderate' => AppColors.warning,
  _ => AppColors.success,
};

String riskBandLabel(String band) => switch (band) {
  'critical' => 'Critical',
  'high' => 'High',
  'moderate' => 'Moderate',
  _ => 'Low',
};

/// Colour for a health-score band.
Color healthBandColor(String? band) => switch (band) {
  'good' => AppColors.success,
  'fair' => AppColors.warning,
  'needs_attention' => const Color(0xFFEA580C),
  'poor' => AppColors.danger,
  _ => const Color(0xFF6B7280),
};

/// Small filled pill used for risk/severity chips.
class MiniPill extends StatelessWidget {
  const MiniPill({super.key, required this.label, required this.color, this.filled = false});

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: filled ? Colors.white : color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
