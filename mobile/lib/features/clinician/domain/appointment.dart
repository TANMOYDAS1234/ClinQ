/// One appointment on the clinic diary, from `GET /api/v1/appointments`.
///
/// Only the fields the doctor's dashboard needs are parsed. Status follows the
/// backend `APPOINTMENT_STATUS` enum:
/// requested · confirmed · checked_in · in_consultation · completed ·
/// cancelled · no_show.
class Appointment {
  const Appointment({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.scheduledFor,
    required this.status,
    required this.mode,
    this.reason,
    this.isPriority = false,
  });

  final String id;
  final String patientId;
  final String patientName;
  final DateTime scheduledFor;

  /// Raw status string from the API (one of APPOINTMENT_STATUS).
  final String status;

  /// `in_clinic` | `teleconsult`.
  final String mode;

  /// Free-text reason for the visit, e.g. "Lab Results Review".
  final String? reason;
  final bool isPriority;

  bool get isCompleted => status == 'completed';

  /// The doctor is with this patient right now (called in or mid-consult).
  bool get isInProgress => status == 'checked_in' || status == 'in_consultation';

  bool get isCancelled => status == 'cancelled' || status == 'no_show';

  /// Still to come — booked/confirmed but not started.
  bool get isUpcoming => !isCompleted && !isInProgress && !isCancelled;

  /// Short human label for the status pill.
  String get statusLabel {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'in_consultation':
        return 'In progress';
      case 'checked_in':
        return 'Checked in';
      case 'confirmed':
        return 'Confirmed';
      case 'requested':
        return 'Requested';
      case 'cancelled':
        return 'Cancelled';
      case 'no_show':
        return 'No show';
      default:
        return status;
    }
  }

  factory Appointment.fromJson(Map<String, dynamic> j) {
    return Appointment(
      id: j['id']?.toString() ?? '',
      patientId: j['patientId']?.toString() ?? '',
      patientName: j['patientName']?.toString() ?? 'Patient',
      scheduledFor:
          DateTime.tryParse(j['scheduledFor']?.toString() ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
      status: j['status']?.toString() ?? 'requested',
      mode: j['mode']?.toString() ?? 'in_clinic',
      reason: (j['reason']?.toString().trim().isEmpty ?? true) ? null : j['reason'].toString().trim(),
      isPriority: j['isPriority'] == true,
    );
  }
}
