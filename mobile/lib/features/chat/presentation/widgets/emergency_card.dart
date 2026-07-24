import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// Rendered whenever `triage.urgency == "emergency"`. This is a
/// patient-safety requirement, not decoration — keep it loud, keep the
/// "Call clinic" action always reachable, and never collapse it behind a
/// tap.
class EmergencyCard extends StatelessWidget {
  const EmergencyCard({super.key, required this.content});

  final String content;

  Future<void> _callClinic() async {
    final uri = Uri(scheme: 'tel', path: AppConfig.clinicPhoneNumber);
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.danger, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Solid red disc — carries the warning independently of colour,
              // which matters for the ~8% of men with colour blindness in a
              // cohort that is mostly men over 45.
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.chatEmergencyBody,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      content,
                      style: const TextStyle(fontSize: 16, height: 1.45, color: Color(0xFF1F2937)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            height: AppSpacing.minTapTarget + 8,
            child: ElevatedButton.icon(
              onPressed: _callClinic,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.danger,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                  side: const BorderSide(color: AppColors.danger, width: 1.5),
                ),
              ),
              icon: const Icon(Icons.call_rounded, size: 22),
              label: Text(
                l10n.chatCallClinic,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
