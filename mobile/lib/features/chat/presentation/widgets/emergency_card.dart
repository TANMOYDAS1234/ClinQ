import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../appointments/data/clinic_repository.dart';

/// Rendered whenever `triage.urgency == "emergency"`. This is a
/// patient-safety requirement, not decoration — keep it loud, keep the
/// "Call clinic" action always reachable, and never collapse it behind a
/// tap.
class EmergencyCard extends ConsumerWidget {
  const EmergencyCard({super.key, required this.content});

  final String content;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // The clinic's own number once the doctor has set one; the built-in number
    // until then — this button must never be left without something to dial.
    final clinicPhone = ref.watch(clinicPhoneProvider).valueOrNull ?? AppConfig.clinicPhoneNumber;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.dangerBgOn(context),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.dangerOn(context), width: 2),
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
                decoration: BoxDecoration(
                  color: AppColors.dangerOn(context),
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
                      style: TextStyle(
                        color: AppColors.dangerOn(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
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
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: clinicPhone)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.danger,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                  side: BorderSide(color: AppColors.dangerOn(context), width: 1.5),
                ),
              ),
              icon: const Icon(Icons.call_rounded, size: 22),
              label: Text(
                l10n.chatCallClinic,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
