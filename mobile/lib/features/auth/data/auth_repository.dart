import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_store.dart';
import '../domain/user.dart';

/// Result of a successful login/register call.
class AuthResult {
  const AuthResult({required this.user, required this.accessToken, required this.refreshToken});

  final AppUser user;
  final String accessToken;
  final String refreshToken;
}

/// Talks to `/auth/*`. Never touches Riverpod or UI state directly — see
/// `AuthController` for the state machine built on top of this.
class AuthRepository {
  AuthRepository(this._client, this._secureStore);

  final ApiClient _client;
  final SecureStore _secureStore;

  Future<AuthResult> register({
    required String name,
    required String phone,
    required String password,
    String? email,
    required String language,
    String? dateOfBirth,
    String? gender,
    String? address,
    double? heightCm,
    double? weightKg,
    int? systolic,
    int? diastolic,
    int? pulse,
    int? spo2,
    int? glucoseMgDl,
    String? complaints,
    String? diabetesType,
    String? inviteCode,
  }) async {
    final json = await _client.postJson(
      '/auth/register',
      body: {
        'name': name,
        'phone': phone,
        'password': password,
        if (email != null && email.isNotEmpty) 'email': email,
        'language': language,
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
        if (gender != null) 'gender': gender,
        if (address != null && address.isNotEmpty) 'address': address,
        if (heightCm != null) 'heightCm': heightCm,
        if (weightKg != null) 'weightKg': weightKg,
        if (systolic != null) 'systolic': systolic,
        if (diastolic != null) 'diastolic': diastolic,
        if (pulse != null) 'pulse': pulse,
        if (spo2 != null) 'spo2': spo2,
        if (glucoseMgDl != null) 'glucoseMgDl': glucoseMgDl,
        if (complaints != null && complaints.isNotEmpty) 'complaints': complaints,
        if (diabetesType != null) 'diabetesType': diabetesType,
        if (inviteCode != null && inviteCode.isNotEmpty) 'inviteCode': inviteCode,
      },
    );
    return _resultFromJson(json);
  }

  Future<AuthResult> login({required String phone, required String password}) async {
    final json = await _client.postJson(
      '/auth/login',
      body: {'phone': phone, 'password': password},
    );
    return _resultFromJson(json);
  }

  Future<void> logout() async {
    try {
      await _client.postJson('/auth/logout');
    } finally {
      await _secureStore.clear();
    }
  }

  /// `GET /auth/me` returns `{ user, profile }`. The profile carries clinical
  /// fields that do not live on the user record — diabetes type among them.
  Future<({AppUser user, String? diabetesType})> getMe() async {
    final json = await _client.getJson('/auth/me');
    final profile = json['profile'];
    return (
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
      diabetesType: profile is Map<String, dynamic> ? profile['diabetesType']?.toString() : null,
    );
  }

  /// Diabetes type lives on `PatientProfile`, not `User`, so it has its own
  /// endpoint — `PATCH /auth/me` would silently ignore it.
  Future<void> updateDiabetesType(String diabetesType) async {
    await _client.patchJson('/auth/me/profile', body: {'diabetesType': diabetesType});
  }

  /// The full `PatientProfile` from `GET /auth/me` — height, diagnosis date,
  /// allergies, emergency contact, targets.
  Future<Map<String, dynamic>> getProfile() async {
    final json = await _client.getJson('/auth/me');
    final profile = json['profile'];
    return profile is Map<String, dynamic> ? profile : <String, dynamic>{};
  }

  /// Updates the clinical profile fields via `PATCH /auth/me/profile`. Only
  /// non-null keys are sent, so an unedited field is left untouched.
  Future<void> updateProfile({
    double? heightCm,
    String? diagnosedOn,
    String? chiefComplaint,
    List<String>? allergies,
    Map<String, String>? emergencyContact,
    Map<String, String>? mealTimes,
  }) async {
    await _client.patchJson(
      '/auth/me/profile',
      body: {
        if (heightCm != null) 'heightCm': heightCm,
        if (diagnosedOn != null) 'diagnosedOn': diagnosedOn,
        if (chiefComplaint != null) 'chiefComplaint': chiefComplaint,
        if (allergies != null) 'allergies': allergies,
        if (emergencyContact != null) 'emergencyContact': emergencyContact,
        if (mealTimes != null) 'mealTimes': mealTimes,
      },
    );
  }

  Future<AppUser> updateMe({
    String? name,
    String? email,
    String? language,
    String? dateOfBirth,
    String? gender,
    String? address,
    String? avatarAssetId,
    String? qualifications,
    String? specialty,
    String? registrationNo,
    String? signatureAssetId,
  }) async {
    final json = await _client.patchJson(
      '/auth/me',
      body: {
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (language != null) 'language': language,
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
        if (gender != null) 'gender': gender,
        if (address != null) 'address': address,
        if (avatarAssetId != null) 'avatarAssetId': avatarAssetId,
        if (qualifications != null) 'qualifications': qualifications,
        if (specialty != null) 'specialty': specialty,
        if (registrationNo != null) 'registrationNo': registrationNo,
        if (signatureAssetId != null) 'signatureAssetId': signatureAssetId,
      },
    );
    return AppUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<AuthResult> _resultFromJson(Map<String, dynamic> json) async {
    final user = AppUser.fromJson(json['user'] as Map<String, dynamic>);
    final accessToken = json['accessToken'] as String;
    final refreshToken = json['refreshToken'] as String;
    await _secureStore.saveTokens(accessToken: accessToken, refreshToken: refreshToken);
    return AuthResult(user: user, accessToken: accessToken, refreshToken: refreshToken);
  }
}
