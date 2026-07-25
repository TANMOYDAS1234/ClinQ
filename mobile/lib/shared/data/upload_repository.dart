import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import '../../core/network/api_client.dart';
import '../providers/core_providers.dart';

/// A file stored by `POST /uploads` (API_CONTRACT.md §12).
class MediaAsset {
  const MediaAsset({
    required this.id,
    required this.kind,
    required this.mimeType,
    required this.sizeBytes,
    this.width,
    this.height,
    this.url,
  });

  final String id;
  final String kind;
  final String mimeType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final String? url;

  factory MediaAsset.fromJson(Map<String, dynamic> json) => MediaAsset(
    id: json['id']?.toString() ?? '',
    kind: json['kind']?.toString() ?? 'other',
    mimeType: json['mimeType']?.toString() ?? 'application/octet-stream',
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    width: (json['width'] as num?)?.toInt(),
    height: (json['height'] as num?)?.toInt(),
    url: json['url']?.toString(),
  );
}

/// Upload kinds the server accepts. Anything else is rejected by its zod enum.
class UploadKind {
  UploadKind._();

  static const String footPhoto = 'foot_photo';
  static const String retinalReport = 'retinal_report';
  static const String labReport = 'lab_report';
  static const String prescriptionPdf = 'prescription_pdf';
  static const String mealPhoto = 'meal_photo';
  static const String avatar = 'avatar';
  static const String other = 'other';
}

/// Talks to `/uploads`.
///
/// The server re-encodes images through sharp, which strips EXIF — patient
/// photos otherwise carry the GPS coordinates of their home.
class UploadRepository {
  UploadRepository(this._client);

  final ApiClient _client;

  /// Server-side limit is `MAX_UPLOAD_MB` (12 by default). Checked here too so
  /// an oversized file fails immediately instead of after a long upload.
  static const int maxBytes = 12 * 1024 * 1024;

  /// MIME types in the server's `ALLOWED_MIME` set.
  static const Set<String> allowedMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'application/pdf',
  };

  Future<MediaAsset> uploadImage({
    required String path,
    required String filename,
    String kind = UploadKind.other,
  }) async {
    final mimeType = _mimeTypeFor(filename);
    final formData = FormData.fromMap({
      'kind': kind,
      'file': await MultipartFile.fromFile(
        path,
        filename: filename,
        contentType: MediaType.parse(mimeType),
      ),
    });
    final json = await _client.postMultipart('/uploads', formData: formData);
    return MediaAsset.fromJson(json);
  }

  static String _mimeTypeFor(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'image/jpeg';
    }
  }
}

final Provider<UploadRepository> uploadRepositoryProvider = Provider<UploadRepository>((ref) {
  return UploadRepository(ref.watch(apiClientProvider));
});
