import 'package:uuid/uuid.dart';

/// Fixed namespace of the execution ids of location stops. Never change it:
/// photos held on a device and the completion sent later derive their shared
/// id from it, so a new value would orphan every photo already taken.
const String _locationExecutionNamespace =
    'cac6897e-477d-4bb2-b1b6-682305d2a84a';

/// The execution id of a location stop (a place concluded by the device
/// position). It has no floor check-in to mint one, yet its photos need an id
/// before the completion exists; deriving it from the route stop keeps it the
/// same on every open of the dialog and for the completion itself.
///
///     locationExecutionId('stop-1') == locationExecutionId('stop-1'); // true
String locationExecutionId(String routeStopId) =>
    const Uuid().v5(_locationExecutionNamespace, routeStopId);
