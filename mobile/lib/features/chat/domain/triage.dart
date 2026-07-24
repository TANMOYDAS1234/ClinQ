/// `triage` object from `POST /chat/message` (API_CONTRACT.md §2).
class Triage {
  const Triage({
    required this.urgency,
    required this.ruleDriven,
    required this.redFlags,
    required this.findings,
    required this.extracted,
  });

  /// routine < advice < urgent < emergency.
  final String urgency;
  final bool ruleDriven;
  final List<RedFlag> redFlags;
  final List<String> findings;

  /// Free-form structured extraction (e.g. `{ "glucoseMgDl": 350 }`);
  /// shape is not enumerated by the contract, kept as a raw map.
  final Map<String, dynamic> extracted;

  bool get isEmergency => urgency == 'emergency';
  bool get isUrgent => urgency == 'urgent';

  factory Triage.fromJson(Map<String, dynamic> json) {
    return Triage(
      urgency: json['urgency']?.toString() ?? 'routine',
      ruleDriven: json['ruleDriven'] as bool? ?? false,
      redFlags: (json['redFlags'] as List<dynamic>? ?? const [])
          .map((e) => RedFlag.fromJson(e as Map<String, dynamic>))
          .toList(),
      findings: (json['findings'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      extracted: (json['extracted'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

class RedFlag {
  const RedFlag({required this.id, required this.label});

  final String id;
  final String label;

  factory RedFlag.fromJson(Map<String, dynamic> json) {
    return RedFlag(id: json['id']?.toString() ?? '', label: json['label']?.toString() ?? '');
  }
}
