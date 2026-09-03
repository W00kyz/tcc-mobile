import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:route_monitor/execution/execution_api.dart'
    show parseServerDate;

/// One evidence item as the backend returns it (`EvidenceItemOut`,
/// `GET /executions/{execution_id}/evidence`).
class EvidenceItem {
  const EvidenceItem({
    required this.id,
    required this.kind,
    required this.capturedAt,
    required this.createdAt,
    this.textBody,
    this.contentType,
    this.byteSize,
    this.contentUrl,
  });

  factory EvidenceItem.fromJson(Map<String, dynamic> json) => EvidenceItem(
    id: json['id'] as String,
    // 'PHOTO' | 'NOTE' — EvidenceKind (backend/app/domain/execution/models.py).
    kind: json['kind'] as String,
    textBody: json['text_body'] as String?,
    capturedAt: DateTime.parse(json['captured_at'] as String),
    contentType: json['content_type'] as String?,
    byteSize: (json['byte_size'] as num?)?.toInt(),
    createdAt: DateTime.parse(json['created_at'] as String),
    contentUrl: json['content_url'] as String?,
  );

  final String id;
  final String kind;
  final String? textBody;
  final DateTime capturedAt;
  final String? contentType;
  final int? byteSize;
  final DateTime createdAt;
  final String? contentUrl;
}

// This interface is the seam that keeps callers off the real HTTP client
// (docs/CLAUDE.base.md — Dependencies: "wrap third-party libs behind a thin
// interface"), same discipline as ExecutionApi.
abstract class EvidenceApi {
  /// Returns the response's `Date` header (null when absent/unparseable) so
  /// the sync worker can measure the clock offset (spec Ruling 7).
  /// [idempotencyKey] is the app-generated UUID the backend dedupes on
  /// (spec Ruling 8) — a known key returns `200` with the existing item.
  Future<DateTime?> uploadPhoto({
    required String executionId,
    required Uint8List bytes,
    required String sha256,
    required DateTime capturedAt,
    required String idempotencyKey,
  });

  Future<DateTime?> uploadNote({
    required String executionId,
    required String textBody,
    required DateTime capturedAt,
    required String idempotencyKey,
  });

  Future<List<EvidenceItem>> listEvidence(String executionId);
}

class DioEvidenceApi implements EvidenceApi {
  DioEvidenceApi(this._dio);

  final Dio _dio;

  @override
  Future<DateTime?> uploadPhoto({
    required String executionId,
    required Uint8List bytes,
    required String sha256,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async {
    final response = await _dio.post<void>(
      '/executions/$executionId/evidence/photo',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: 'evidence.jpg'),
        'sha256': sha256,
        'captured_at': capturedAt.toUtc().toIso8601String(),
        'idempotency_key': idempotencyKey,
      }),
    );
    return parseServerDate(response.headers);
  }

  @override
  Future<DateTime?> uploadNote({
    required String executionId,
    required String textBody,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async {
    final response = await _dio.post<void>(
      '/executions/$executionId/evidence/note',
      data: {
        'text_body': textBody,
        'captured_at': capturedAt.toUtc().toIso8601String(),
        'idempotency_key': idempotencyKey,
      },
    );
    return parseServerDate(response.headers);
  }

  @override
  Future<List<EvidenceItem>> listEvidence(String executionId) async {
    final response = await _dio.get<List<dynamic>>(
      '/executions/$executionId/evidence',
    );
    return response.data!
        .map((raw) => EvidenceItem.fromJson(raw as Map<String, dynamic>))
        .toList();
  }
}
