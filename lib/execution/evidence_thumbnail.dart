import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/execution/evidence_list.dart';
import 'package:route_monitor/execution/execution_providers.dart';

/// A square thumbnail of one evidence photo: the local bytes while the
/// upload is still queued, the backend copy once synced, nothing for a note.
/// Shared by the stop's evidence list and the form's MEDIA question.
///
/// ```dart
/// EvidenceThumbnail(entry, size: 72)
/// ```
class EvidenceThumbnail extends ConsumerWidget {
  const EvidenceThumbnail(this.item, {this.size = 40, super.key});

  final EvidenceListEntry item;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item.kind != 'PHOTO') return const SizedBox.shrink();
    final bytes = item.photoBytes;
    if (bytes != null) {
      return Image.memory(bytes, width: size, height: size, fit: BoxFit.cover);
    }
    final contentUrl = item.contentUrl;
    if (contentUrl == null) return const SizedBox.shrink();
    // NetworkImage's own `headers` map is enough for the bearer token here
    // — simpler than a custom Dio-backed ImageProvider, and the offline
    // map screen already established that a plain network fetch (no
    // redirect handling needed) is fine for this backend. Reads the base
    // URL through apiBaseUrlProvider (not apiBaseUrlFromEnvironment()
    // directly) so a test can override it with a fixed value instead of
    // requiring a real --dart-define.
    final token = ref.watch(sessionProvider)?.accessToken;
    final baseUrl = ref.watch(apiBaseUrlProvider);
    return Image(
      image: NetworkImage(
        '$baseUrl$contentUrl',
        headers: token == null ? null : {'Authorization': 'Bearer $token'},
      ),
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
  }
}
