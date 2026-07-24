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
      createdAt: _parseDate(json['createdAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  AppUser copyWith({String? language}) {
    return AppUser(
      id: id,
      name: name,
      phone: phone,
      role: role,
      language: language ?? this.language,
      email: email,
      dateOfBirth: dateOfBirth,
      gender: gender,
      createdAt: createdAt,
    );
  }
}
