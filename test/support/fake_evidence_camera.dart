import 'package:flutter/widgets.dart';
import 'package:route_monitor/execution/evidence_camera.dart';

/// An [EvidenceCamera] that never touches the platform: each shot returns a
/// fresh fake path.
class FakeEvidenceCamera implements EvidenceCamera {
  FakeEvidenceCamera({this.openError});

  final Error? openError;
  int shots = 0;
  bool closed = false;

  @override
  Future<void> open() async {
    if (openError != null) throw openError!;
  }

  @override
  Widget preview() => const SizedBox(key: Key('fake-preview'));

  @override
  Future<String> takePicture() async => '/fake/shot-${++shots}.jpg';

  @override
  Future<void> close() async => closed = true;
}
