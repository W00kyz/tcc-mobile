import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/api/env.dart';
import 'package:route_monitor/checkin/qr_verifier.dart';

final qrVerifierProvider = Provider<QrVerifier>(
  (ref) => QrVerifier(qrPublicKeyHexFromEnvironment()),
);
