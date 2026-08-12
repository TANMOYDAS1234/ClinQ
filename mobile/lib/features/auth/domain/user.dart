/// Matches the `User` object in API_CONTRACT.md §1.
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    required this.language,
    this.email,
    this.dateOfBirth,
    this.gender,
    this.avatarUrl,
    this.qualifications,
    this.specialty,
    this.registrationNo,
    this.signatureUrl,
    this.createdAt,
  });

  final String id;
  final String name;
  final String phone;
  final String? email;

  /// `patient` | `doctor` | `staff` (contract does not enumerate exhaustively;
  /// treated as an opaque string).
  final String role;

  /// `en` | `bn` | `hi`.
  final String language;

  final DateTime? dateOfBirth;

  /// `male` | `female` | `other`.
  final String? gender;

  /// Relative `/api/v1/uploads/:id/raw` path of the profile photo, or null.
  final String? avatarUrl;

  /// Doctor letterhead fields (null for patients/staff). `qualifications` like
  /// "MBBS, MD"; `registrationNo` the medical-council number; `signatureUrl` the
  /// uploaded signature image, embedded into prescription PDFs.
  final String? qualifications;
  final String? specialty;
  final String? registrationNo;
  final String? signatureUrl;

  final DateTime? createdAt;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      email: json['email'] as String?,
      role: json['role']?.toString() ?? 'patient',
      language: json['language']?.toString() ?? 'en',
      dateOfBirth: _parseDate(json['dateOfBirth']),
      gender: json['gender'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      qualifications: json['qualifications'] as String?,
      specialty: json['specialty'] as String?,
      registrationNo: json['registrationNo'] as String?,
      signatureUrl: json['signatureUrl'] as String?,
      createdAt: _parseDate(json['createdAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  AppUser copyWith({String? language, String? avatarUrl}) {
    return AppUser(
      id: id,
      name: name,
      phone: phone,
      role: role,
      language: language ?? this.language,
      email: email,
      dateOfBirth: dateOfBirth,
      gender: gender,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      qualifications: qualifications,
      specialty: specialty,
      registrationNo: registrationNo,
      signatureUrl: signatureUrl,
      createdAt: createdAt,
    );
  }
}
