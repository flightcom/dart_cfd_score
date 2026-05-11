// In-memory flight track plus the caches the solver populates as it runs.
//
// The caches mirror what `geom.init()` attaches to `opt.flight` in
// igc-xc-score: a closest-pair memo (rbush in JS — here a plain list with
// linear filter, see CHANGELOG) and a furthest-point memo (one per direction).

import 'foundation.dart';

/// Memoized closest-pair entry.
/// Semantically: for all queries with `p1 ∈ [minX..maxX]` and
/// `p2 ∈ [minY..maxY]`, the closest pair across `[launch..p1]` × `[p2..landing]`
/// has the value `o`.
class ClosestPairEntry {
  ClosestPairEntry({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.pIn,
    required this.pOut,
    required this.d,
  });
  // Index-space rectangle of the queries this entry answers.
  final int minX;
  final int minY;
  final int maxX;
  final int maxY;
  // The cached closest pair.
  final Point pIn;
  final Point pOut;
  final double d;
}

/// Memoized furthest-point entry. `[min, max]` is the index-space range of
/// segb (when seeking from launch) or sega (when seeking from landing) over
/// which `o` remains the furthest point from `(vx, vy)`.
class FurthestPointEntry {
  FurthestPointEntry({required this.min, required this.max, required this.o});
  int min;
  int max;
  final Point o;
}

class FlightState {
  FlightState(this.filtered)
      : flightPoints = List<Point>.generate(
          filtered.length,
          (int i) => Point(filtered[i].x, filtered[i].y, r: i),
          growable: false,
        );

  /// Raw filtered fixes (one per accepted GPS sample).
  final List<Point> filtered;

  /// Same fixes, each with `r` set to its index — what the solver hands to
  /// scoring callbacks as turnpoints.
  final List<Point> flightPoints;

  /// Closest-pair memo (used by triangle-closure checks). Linear scan on
  /// insert/query — adequate for typical flight sizes; replace with a real
  /// 2D index if it ever shows up in profiles.
  final List<ClosestPairEntry> closestPairs = <ClosestPairEntry>[];

  /// Furthest-point memo. Index 0 = "sega == launch" direction, index 1 =
  /// "segb == landing" direction. Key = `"${v.x}:${v.y}"`.
  final List<Map<String, List<FurthestPointEntry>>> furthestPoints =
      <Map<String, List<FurthestPointEntry>>>[
    <String, List<FurthestPointEntry>>{},
    <String, List<FurthestPointEntry>>{},
  ];
}
