import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/secure_store.dart';
import 'api_exception.dart';

/// Endpoints that must be called without an `Authorization` header and that
/// must never trigger the refresh-and-retry flow.
const _publicPaths = <String>['/auth/register', '/auth/login', '/auth/refresh', '/health'];

/// Wraps a configured [Dio] instance with:
///  - base URL / timeouts from [AppConfig]
///  - a bearer-token auth interceptor
///  - automatic refresh-and-retry-once on a 401 response
///  - mapping of every failure into an [ApiException] so callers never see
///    raw [DioException]s.
///
/// Repositories should depend on this class only — never construct their
/// own [Dio].
class ApiClient {
  ApiClient({required SecureStore secureStore, VoidCallback? onAuthExpired})
    : _secureStore = secureStore,
      _onAuthExpired = onAuthExpired,
      _dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: AppConfig.connectTimeout,
          receiveTimeout: AppConfig.receiveTimeout,
          headers: const {'Content-Type': 'application/json'},
        ),
      ),
      // Bare client used only for the token-refresh call itself, so that
      // refreshing never recurses through the auth interceptor below.
      _refreshDio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: AppConfig.connectTimeout,
          receiveTimeout: AppConfig.receiveTimeout,
          headers: const {'Content-Type': 'application/json'},
        ),
      ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final isPublic = _publicPaths.any((p) => options.path.startsWith(p));
          if (!isPublic) {
            final token = await _secureStore.readAccessToken();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final isPublic = _publicPaths.any((p) => error.requestOptions.path.startsWith(p));
          final alreadyRetried = error.requestOptions.extra['akdRetried'] == true;

          if (!isPublic && error.response?.statusCode == 401 && !alreadyRetried) {
            try {
              final newAccessToken = await _refreshAccessToken();
              if (newAccessToken != null) {
                final retryOptions = error.requestOptions;
                retryOptions.extra['akdRetried'] = true;
                retryOptions.headers['Authorization'] = 'Bearer $newAccessToken';
                final response = await _dio.fetch(retryOptions);
                handler.resolve(response);
                return;
              }
            } catch (_) {
              // fall through to auth-expired handling below
            }
            await _secureStore.clear();
            _onAuthExpired?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final Dio _refreshDio;
  final SecureStore _secureStore;
  final VoidCallback? _onAuthExpired;

  // Ensures concurrent 401s trigger exactly one refresh call.
  Completer<String?>? _refreshInFlight;

  Future<String?> _refreshAccessToken() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight.future;

    final completer = Completer<String?>();
    _refreshInFlight = completer;

    () async {
      try {
        final refreshToken = await _secureStore.readRefreshToken();
        if (refreshToken == null || refreshToken.isEmpty) {
          completer.complete(null);
          return;
        }
        final response = await _refreshDio.post(
          '/auth/refresh',
          data: {'refreshToken': refreshToken},
        );
        final data = response.data as Map<String, dynamic>;
        final newAccess = data['accessToken'] as String?;
        final newRefresh = data['refreshToken'] as String?;
        if (newAccess == null || newRefresh == null) {
          completer.complete(null);
          return;
        }
        await _secureStore.saveTokens(accessToken: newAccess, refreshToken: newRefresh);
        completer.complete(newAccess);
      } catch (_) {
        completer.complete(null);
      } finally {
        _refreshInFlight = null;
      }
    }();

    return completer.future;
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _run(() => _dio.get(path, queryParameters: _cleanQuery(query)));
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    final response = await _run(
      () => _dio.post(path, data: body, queryParameters: _cleanQuery(query)),
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    Object? body,
  }) async {
    final response = await _run(() => _dio.patch(path, data: body));
    return _asMap(response.data);
  }

  Future<void> delete(String path) async {
    await _run(() => _dio.delete(path));
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required FormData formData,
  }) async {
    final response = await _run(() => _dio.post(path, data: formData));
    return _asMap(response.data);
  }

  Map<String, dynamic>? _cleanQuery(Map<String, dynamic>? query) {
    if (query == null) return null;
    final cleaned = <String, dynamic>{};
    for (final entry in query.entries) {
      if (entry.value != null) cleaned[entry.key] = entry.value;
    }
    return cleaned;
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data == null) return const {};
    return {'value': data};
  }

  Future<Response<dynamic>> _run(Future<Response<dynamic>> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  ApiException _mapError(DioException e) {
    final response = e.response;
    if (response == null) {
      final isTimeout =
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout;
      return ApiException(
        code: isTimeout ? 'TIMEOUT' : 'NETWORK_ERROR',
        message: e.message ?? 'Network error',
      );
    }

    final data = response.data;
    if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
      final error = data['error'] as Map<String, dynamic>;
      final rawDetails = error['details'];
      final details = <ApiErrorDetail>[];
      if (rawDetails is List) {
        for (final d in rawDetails) {
          if (d is Map<String, dynamic>) details.add(ApiErrorDetail.fromJson(d));
        }
      }
      return ApiException(
        code: error['code']?.toString() ?? 'UNKNOWN',
        message: error['message']?.toString() ?? 'Request failed',
        details: details,
        statusCode: response.statusCode,
      );
    }

    return ApiException(
      code: 'UNKNOWN',
      message: 'Request failed with status ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }
}

typedef VoidCallback = void Function();
