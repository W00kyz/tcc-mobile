import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/evidence_camera.dart';
import 'package:route_monitor/execution/evidence_photo_count.dart';
import 'package:route_monitor/execution/evidence_requirement.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/photo_sequence_viewer.dart';
import 'package:route_monitor/execution/photo_sequence_widgets.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/ui/app_theme.dart';

/// Opens the full-screen photo camera for one stop and returns how many
/// photos of this session are still kept when it closes. [minimum] is
/// `MIN_EVIDENCE_PHOTOS` for a `requires_evidence` stop, null otherwise.
Future<int> openPhotoSequence(
  BuildContext context, {
  required String routeId,
  required String executionId,
  required String buildingName,
  required String floorLabel,
  required int? minimum,
}) async {
  final taken = await Navigator.of(context).push<int>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PhotoSequenceScreen(
        routeId: routeId,
        executionId: executionId,
        title: AppStrings.photoSequenceTitle(buildingName, floorLabel),
        minimum: minimum,
      ),
    ),
  );
  return taken ?? 0;
}

class PhotoSequenceScreen extends ConsumerStatefulWidget {
  const PhotoSequenceScreen({
    required this.routeId,
    required this.executionId,
    required this.title,
    required this.minimum,
    super.key,
  });

  final String routeId;
  final String executionId;
  final String title;
  final int? minimum;

  @override
  ConsumerState<PhotoSequenceScreen> createState() => _State();
}

class _State extends ConsumerState<PhotoSequenceScreen> {
  late final EvidenceCamera _camera = ref.read(evidenceCameraProvider);
  final List<SessionShot> _shots = [];
  Set<String> _unsynced = {};
  bool _ready = false;
  bool _failed = false;
  bool _busy = false;

  (String, String) get _query => (widget.routeId, widget.executionId);

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    unawaited(_camera.close());
    super.dispose();
  }

  Future<void> _open() async {
    try {
      await _camera.open();
      if (mounted) setState(() => _ready = true);
      // Deliberately broad: no camera, permission denied or any plugin error
      // all mean the same here — show the message, keep the screen closable.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _refreshUnsynced() async {
    final rows = await ref
        .read(localWriteStoreProvider)
        .unsyncedForRoute(widget.routeId);
    _unsynced = rows.map((row) => row.id).toSet();
  }

  /// Compress, write to SQLite, and only then show the thumbnail (RNF06).
  Future<void> _shoot() async {
    setState(() => _busy = true);
    try {
      final path = await _camera.takePicture();
      final photo = await ref.read(capturedFileCompressorProvider)(path);
      final id = await ref
          .read(executionRepositoryProvider)
          .addPhoto(
            routeId: widget.routeId,
            executionId: widget.executionId,
            photo: photo,
          );
      _invalidateCounts();
      await _refreshUnsynced();
      if (mounted) {
        setState(() => _shots.add(SessionShot(id: id, bytes: photo.bytes)));
      }
      // Deliberately broad, same discipline as the other capture paths.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      _showError(AppStrings.photoSequenceSaveError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invalidateCounts() {
    ref
      ..invalidate(localPhotoCountProvider(widget.executionId))
      ..invalidate(stopEvidenceProvider(_query));
  }

  /// Floats the message under the title bar so it never covers the shutter.
  void _showError(String message) {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top + 96;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, size.height - top - 56),
      ),
    );
  }

  Future<void> _openShot(SessionShot shot) async {
    await _refreshUnsynced();
    if (!mounted) return;
    final delete = await showShotViewer(
      context,
      shot: shot,
      deletable: _unsynced.contains(shot.id),
    );
    if (delete) await _delete(shot);
  }

  Future<void> _delete(SessionShot shot) async {
    final removed = await ref
        .read(localWriteStoreProvider)
        .deletePendingPhoto(shot.id);
    if (!removed) {
      _showError(AppStrings.photoSequenceDeleteError);
      return;
    }
    _invalidateCounts();
    if (mounted) setState(() => _shots.remove(shot));
  }

  void _close() => Navigator.of(context).pop(_shots.length);

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(stopPhotoCountProvider(_query)) ?? _shots.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // A shot in flight must land in SQLite first: back is a no-op then.
        if (!didPop && !_busy) _close();
      },
      child: Scaffold(
        backgroundColor: kCameraChrome,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _viewfinder(),
            _topBar(count),
            Align(alignment: Alignment.bottomCenter, child: _dock(count)),
          ],
        ),
      ),
    );
  }

  Widget _viewfinder() {
    if (_ready) return _camera.preview();
    if (!_failed) return const SizedBox.shrink();
    return const Center(
      child: Text(
        AppStrings.photoSequenceCameraError,
        style: TextStyle(color: kCameraSoftText),
      ),
    );
  }

  Widget _topBar(int count) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kCameraTopFade, kCameraTopFade.withValues(alpha: 0)],
        ),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 12, 24),
            child: Row(
              children: [
                IconButton(
                  key: const Key('photo-close'),
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  tooltip: AppStrings.photoSequenceClose,
                  icon: const Icon(Icons.close, color: kScanOverlayWhite),
                  onPressed: _busy ? null : _close,
                ),
                Expanded(child: _title()),
                CounterPill(count: count, minimum: widget.minimum),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _title() => Text(
    widget.title,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      color: kScanOverlayWhite,
      fontSize: 17,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _dock(int count) {
    final min = widget.minimum;
    final missing = min == null ? 0 : (min - count).clamp(0, min);
    final capped = !canAddEvidencePhoto(
      requiresEvidence: min != null,
      photoCount: count,
    );
    return Container(
      width: double.infinity,
      color: kCameraDock,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _strip(),
            const SizedBox(height: 12),
            _controls(
              canShoot: _ready && !_busy && !capped,
              missing: missing,
            ),
          ],
        ),
      ),
    );
  }

  Widget _strip() {
    final slots = (widget.minimum ?? 0) - _shots.length;
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (i, shot) in _shots.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ShotThumbnail(
                key: Key('photo-thumb-$i'),
                shot: shot,
                number: i + 1,
                synced: !_unsynced.contains(shot.id),
                onTap: () => _openShot(shot),
              ),
            ),
          for (var n = 1; n <= slots; n++)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: PendingSlot(number: _shots.length + n),
            ),
        ],
      ),
    );
  }

  Widget _controls({required bool canShoot, required int missing}) {
    return SizedBox(
      width: double.infinity,
      height: 104,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ShutterButton(
              key: const Key('photo-shutter'),
              onTap: canShoot ? _shoot : null,
            ),
          ),
          Positioned(
            right: 0,
            top: 16,
            child: DoneButton(
              key: const Key('photo-done'),
              missing: missing,
              onTap: missing == 0 && !_busy ? _close : null,
            ),
          ),
        ],
      ),
    );
  }
}
