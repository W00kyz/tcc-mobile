import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/evidence_capture.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/execution_repository.dart';

/// Takes one photo for a MEDIA form question: opens the camera, queues the
/// photo as ordinary evidence of the execution, and returns the key the
/// answer lists — or null when the field worker cancels the camera.
///
/// ```dart
/// final key = await ref.read(mediaPhotoTakerProvider).take(
///   routeId: routeId, executionId: executionId);
/// ```
// ignore: one_member_abstracts
abstract class MediaPhotoTaker {
  Future<String?> take({required String routeId, required String executionId});
}

/// Camera (no gallery: the evidence is of the moment of execution) plus the
/// same offline queue the loose evidence photos use, so the photo uploads
/// before the check-out that answers with its key (FIFO per route).
class DeviceMediaPhotoTaker implements MediaPhotoTaker {
  DeviceMediaPhotoTaker(this._capture, this._repository);

  final EvidenceCapture _capture;
  final ExecutionRepository _repository;

  @override
  Future<String?> take({
    required String routeId,
    required String executionId,
  }) async {
    final photo = await _capture.takePhoto();
    if (photo == null) return null;
    return _repository.addPhoto(
      routeId: routeId,
      executionId: executionId,
      photo: photo,
    );
  }
}

final mediaPhotoTakerProvider = Provider<MediaPhotoTaker>(
  (ref) => DeviceMediaPhotoTaker(
    ref.watch(evidenceCaptureProvider),
    ref.watch(executionRepositoryProvider),
  ),
);
