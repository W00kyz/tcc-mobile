import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

/// The seam over the `camera` package (spec §6.5): the photo-sequence screen
/// and its tests never touch the platform camera (docs/CLAUDE.base.md —
/// "wrap third-party libs behind a thin interface"). Camera only; there is no
/// gallery path.
abstract class EvidenceCamera {
  /// Starts the back camera. Throws if it is unavailable or permission is
  /// denied.
  Future<void> open();

  /// The live viewfinder; valid only after [open] completed.
  Widget preview();

  /// Takes one picture and returns the path of its file.
  Future<String> takePicture();

  /// Releases the camera. Safe to call without a successful [open].
  Future<void> close();
}

/// [EvidenceCamera] over `package:camera`: back camera, high resolution,
/// flash off.
class DeviceEvidenceCamera implements EvidenceCamera {
  CameraController? _controller;

  @override
  Future<void> open() async {
    final cameras = await availableCameras();
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _controller = controller;
    await controller.initialize();
    await controller.setFlashMode(FlashMode.off);
  }

  @override
  Widget preview() => CameraPreview(_controller!);

  @override
  Future<String> takePicture() async => (await _controller!.takePicture()).path;

  @override
  Future<void> close() async {
    await _controller?.dispose();
    _controller = null;
  }
}
