/// How a stop is concluded: by scanning the floor's QR (rooms) or by being at
/// the place (outdoor places, confirmed by GPS).
enum StopCompletion {
  qr,
  location;

  /// The backend's `completion` value. Anything but `LOCATION` — including
  /// null, from a snapshot cached before places existed — is a QR stop.
  ///
  ///     StopCompletion.parse('LOCATION'); // StopCompletion.location
  ///     StopCompletion.parse(null);       // StopCompletion.qr
  static StopCompletion parse(String? raw) =>
      raw == 'LOCATION' ? StopCompletion.location : StopCompletion.qr;
}
