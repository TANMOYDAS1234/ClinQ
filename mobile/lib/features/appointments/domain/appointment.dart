/// A booked appointment, as returned by `/appointments`.
class Appointment {
  const Appointment({
    required this.id,
    required this.scheduledFor,
    required this.status,
    required this.mode,
    this.durationMinutes = 15,
    this.patientId,
    this.patientName,
    this.patientPhone,
    this.doctorName,
    this.clinicId,
    this.clinicName,
    this.clinicAddress,
    this.clinicCity,
    this.clinicPhone,
    this.reason,
    this.queueNumber,
    this.isPriority = false,
    this.consultationNotes,
    this.createdAt,
  });

  final String id;
  final DateTime scheduledFor;

  /// requested | confirmed | checked_in | in_consultation | completed |
  /// cancelled | no_show
  final String status;

  /// in_clinic | teleconsult
  final String mode;
  final int durationMinutes;

  final String? patientId;
  final String? patientName;
  final String? patientPhone;
  final String? doctorName;

  final String? clinicId;
  final String? clinicName;
  final String? clinicAddress;
  final String? clinicCity;
  final String? clinicPhone;

  final String? reason;
  final int? queueNumber;
  final bool isPriority;
  final String? consultationNotes;
  final DateTime? createdAt;

  bool get isTeleconsult => mode == 'teleconsult';
  bool get isCancelled => status == 'cancelled';
  bool get isCompleted => status == 'completed';
  bool get isPast => scheduledFor.isBefore(DateTime.now());

  /// Whether the patient can still act on it (cancel / reschedule).
  bool get isActive =>
      status == 'requested' || status == 'confirmed' || status == 'checked_in' || status == 'in_consultation';

  factory Appointment.fromJson(Map<String, dynamic> j) {
    final clinic = j['clinic'];
    final clinicMap = clinic is Map<String, dynamic> ? clinic : const <String, dynamic>{};
    return Appointment(
      id: j['id']?.toString() ?? '',
      scheduledFor: DateTime.tryParse(j['scheduledFor']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      status: j['status']?.toString() ?? 'requested',
      mode: j['mode']?.toString() ?? 'in_clinic',
      durationMinutes: (j['durationMinutes'] as num?)?.toInt() ?? 15,
      patientId: j['patientId']?.toString(),
      patientName: j['patientName']?.toString(),
      patientPhone: j['patientPhone']?.toString(),
      doctorName: j['doctorName']?.toString(),
      clinicId: (clinicMap['id'] ?? j['clinicId'])?.toString(),
      clinicName: clinicMap['name']?.toString(),
      clinicAddress: clinicMap['addressLine']?.toString(),
      clinicCity: clinicMap['city']?.toString(),
      clinicPhone: clinicMap['phone']?.toString(),
      reason: j['reason']?.toString(),
      queueNumber: (j['queueNumber'] as num?)?.toInt(),
      isPriority: j['isPriority'] == true,
      consultationNotes: j['consultationNotes']?.toString(),
      createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal(),
    );
  }
}
