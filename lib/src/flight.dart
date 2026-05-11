// Local-format adapter (NOT a port of igc-xc-score/src/flight.js).
//
// The Flutter app stores flights as a JSON list of GPS fixes (lat, lon,
// timestampMs). This adapter wraps that list into a [FlightState] the solver
// can run on. Launch/landing detection from the IGC parser is intentionally
// omitted — the upstream app already trims its tracks, so we treat the whole
// list as one flight `[0..len-1]`.

import 'flight_state.dart';
import 'foundation.dart';

class FlightFix {
  const FlightFix({
    required this.latitude,
    required this.longitude,
    required this.timestampMs,
  });

  /// Convenience constructor for the Flutter app's local JSON shape.
  factory FlightFix.fromJson(Map<String, Object?> json) => FlightFix(
        latitude: (json['lat'] ?? json['latitude']) as double,
        longitude: (json['lon'] ?? json['longitude']) as double,
        timestampMs: (json['timestampMs'] ?? json['ts']) as int,
      );

  final double latitude;
  final double longitude;
  final int timestampMs;
}

/// Build a [FlightState] from a list of local-format fixes.
FlightState flightStateFromFixes(List<FlightFix> fixes) {
  final List<Point> pts = <Point>[
    for (final FlightFix f in fixes) Point(f.longitude, f.latitude),
  ];
  return FlightState(pts);
}
