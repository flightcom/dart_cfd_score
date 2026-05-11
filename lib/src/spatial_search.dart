// Ported from igc-xc-score/src/geom.js (LGPL-3.0) — spatial-search half.
//
// Closest-pair / furthest-point / triangle-closure helpers. These depend on
// Flatbush (k-NN over a packed Hilbert R-tree) and on flight-level caches
// (`FlightState.closestPairs`, `FlightState.furthestPoints`).

import 'dart:math' as math;

import 'flatbush.dart';
import 'flight_state.dart';
import 'foundation.dart';
import 'opt.dart';
import 'scoring_rule.dart';
import 'util.dart';

/// Result of `findClosestPairIn2Segments` / `findClosestPairIn2PartialSegments`.
/// Mirrors the JS `{ d, in, out }` literal — kept as a struct so the caller
/// can read the closing distance and the two on-track points.
class ClosestPair {
  ClosestPair({required this.d, this.pIn, this.pOut});
  double d;
  Point? pIn;
  Point? pOut;
}

/// Closest pair `(pIn, pOut)` such that `pIn` lies in `[launch..p1]` and
/// `pOut` lies in `[p2..landing]`. O(n log n) per call via a Hilbert R-tree
/// rebuilt on `[launch..p1]`; subsequent calls hit a cache keyed on the
/// (p1, p2) pair (linear scan — see `FlightState.closestPairs`).
ClosestPair findClosestPairIn2Segments(int p1, int p2, SolverOpt opt) {
  final FlightState flight = opt.flight;

  // Cache lookup: any entry whose index-space rectangle covers (p1, p2).
  ClosestPairEntry? bestIn;
  ClosestPairEntry? bestOut;
  for (final ClosestPairEntry e in flight.closestPairs) {
    if (e.minX <= p1 && p1 <= e.maxX && e.minY <= p2 && p2 <= e.maxY) {
      // JS reduces by maximizing `x.in` then minimizing `x.out`, but the value
      // returned is just `precomputed.o` from whichever reduce ran last (over
      // the same candidate set). Replicate verbatim.
      if (bestIn == null || (e.pIn.r ?? -1) > (bestIn.pIn.r ?? -1)) bestIn = e;
      if (bestOut == null || (e.pOut.r ?? -1) < (bestOut.pOut.r ?? 1 << 30)) {
        bestOut = e;
      }
    }
  }
  // JS final value is `bestOut ?? bestIn` (reduce chain).
  final ClosestPairEntry? precomputed = bestOut ?? bestIn;
  if (precomputed != null) {
    return ClosestPair(
        d: precomputed.d, pIn: precomputed.pIn, pOut: precomputed.pOut);
  }

  // Build a Flatbush over [launch..p1], using x scaled by cos(lat) for an
  // approximate equirectangular metric — kept identical to JS so the k-NN
  // ordering matches.
  final int n = p1 + 1 - opt.launch;
  final Flatbush rtree = Flatbush(n, 8);
  final double lc =
      math.cos(radians(flight.flightPoints[p1].y)).abs();
  for (int i = opt.launch; i <= p1; i++) {
    final Point r = flight.flightPoints[i];
    rtree.add(r.x * lc, r.y, r.x * lc, r.y);
  }
  rtree.finish();

  // Trim the search range using prior cached entries: anything past
  // `lastUnknown` is already covered by an existing entry.
  ClosestPairEntry? nextEntry;
  for (final ClosestPairEntry e in flight.closestPairs) {
    if (e.minX <= p1 &&
        p1 <= e.maxX &&
        e.minY <= p2 &&
        opt.landing <= e.maxY) {
      if (nextEntry == null ||
          (e.pOut.r ?? 1 << 30) < (nextEntry.pOut.r ?? 1 << 30)) {
        nextEntry = e;
      }
    }
  }
  final int lastUnknown = nextEntry != null ? nextEntry.maxY : opt.landing;

  ClosestPair min = ClosestPair(d: double.infinity);
  for (int i = p2; i <= lastUnknown; i++) {
    final Point pout = flight.flightPoints[i];
    final List<int> neigh =
        rtree.neighbors(pout.x * lc, pout.y, maxResults: 1);
    if (neigh.isEmpty) continue;
    final int idx = neigh[0] + opt.launch;
    final Point pin = flight.flightPoints[idx];
    final double d = opt.scoring.rounding(pout.distanceEarth(pin));
    if (d < min.d) {
      min = ClosestPair(d: d, pIn: pin, pOut: pout);
    }
  }

  if (nextEntry != null) {
    final Point pout = nextEntry.pOut;
    final Point pin = nextEntry.pIn;
    final double d = opt.scoring.rounding(pout.distanceEarth(pin));
    if (d < min.d) {
      min = ClosestPair(d: d, pIn: pin, pOut: pout);
    }
  }

  flight.closestPairs.add(ClosestPairEntry(
    minX: min.pIn!.r!,
    minY: p2,
    maxX: p1,
    maxY: min.pOut!.r!,
    pIn: min.pIn!,
    pOut: min.pOut!,
    d: min.d,
  ));
  return min;
}

/// Closest pair between two arbitrary index ranges. Used for out-and-return
/// closure (no caching — matches the JS implementation's `// TODO`).
ClosestPair findClosestPairIn2PartialSegments(
    Range rangeA, Range rangeB, SolverOpt opt) {
  final FlightState flight = opt.flight;
  final int n = rangeA.end + 1 - rangeA.start;
  final Flatbush rtree = Flatbush(n);
  final double lc =
      math.cos(radians(flight.flightPoints[rangeA.start].y)).abs();
  for (int i = rangeA.start; i <= rangeA.end; i++) {
    final Point r = flight.flightPoints[i];
    rtree.add(r.x * lc, r.y, r.x * lc, r.y);
  }
  rtree.finish();

  ClosestPair min = ClosestPair(d: double.infinity);
  for (int i = rangeB.start; i <= rangeB.end; i++) {
    final Point pout = flight.flightPoints[i];
    final List<int> neigh =
        rtree.neighbors(pout.x * lc, pout.y, maxResults: 1);
    if (neigh.isEmpty) continue;
    final int idx = neigh[0] + rangeA.start;
    final Point pin = flight.flightPoints[idx];
    final double d = opt.scoring.rounding(pout.distanceEarth(pin));
    if (d < min.d) {
      min = ClosestPair(d: d, pIn: pin, pOut: pout);
    }
  }
  return min;
}

/// Furthest point from `target` over track range `[sega..segb]`. Supported
/// only when `sega == launch` (pos 0) or `segb == landing` (pos 1) — that's
/// how the cache stays sound. Used to place the entry/exit of a 3TP open
/// flight without enumerating those as turnpoints.
///
/// Returns a [Point] in the common case, or the [Box] `target` itself when
/// `target` is a Box that overlaps the search segment (degenerate case,
/// matches the JS behavior — the caller passes it into
/// [geom.maxDistanceNRectangles] which accepts both).
Object findFurthestPointInSegment(
    int sega, int segb, Object target, SolverOpt opt) {
  final FlightState flight = opt.flight;
  late final List<Point> points;
  if (target is Box) {
    points = target.vertices();
  } else if (target is Point) {
    points = <Point>[target];
  } else {
    throw ArgumentError('target must be either Point or Box');
  }

  int pos;
  int zSearch;
  if (sega == opt.launch) {
    pos = 0;
    zSearch = segb;
  } else if (segb == opt.landing) {
    pos = 1;
    zSearch = sega;
  } else {
    throw RangeError(
        'findFurthestPointInSegment supports seeking only from launch or landing');
  }

  double distanceMax = double.negativeInfinity;
  Object? fpoint;

  for (final Point v in points) {
    double distanceVMax = double.negativeInfinity;
    Object? fVpoint;

    final String key = '${v.x}:${v.y}';
    final List<FurthestPointEntry>? precomputedAll =
        flight.furthestPoints[pos][key];

    FurthestPointEntry? precomputed;
    if (precomputedAll != null) {
      for (final FurthestPointEntry p in precomputedAll) {
        if (zSearch >= p.min && zSearch <= p.max) {
          precomputed = p;
          break;
        }
      }
    }

    if (precomputed != null) {
      final int r = precomputed.o.r ?? -1;
      if (sega <= r && r <= segb) {
        distanceVMax = v.distanceEarth(precomputed.o);
        fVpoint = precomputed.o;
      } else {
        throw StateError('furthestPoints cache inconsistency');
      }
    }

    if (fVpoint == null) {
      bool intersecting = false;
      bool canCache = false;
      for (int p = sega; p <= segb; p++) {
        final Point f = flight.flightPoints[p];
        if (target is Box && target.intersectsPoint(f)) {
          intersecting = true;
          continue;
        }
        final double d = v.distanceEarth(f);
        if (d > distanceVMax) {
          distanceVMax = d;
          fVpoint = f;
          canCache = true;
        }
      }
      if (intersecting) {
        for (final Point p in points) {
          final double d = v.distanceEarth(p);
          if (d > distanceVMax) {
            distanceVMax = d;
            fVpoint = target;
            canCache = false;
          }
        }
      }
      if (canCache && fVpoint is Point) {
        int zMin;
        int zMax;
        if (sega == opt.launch) {
          zMin = fVpoint.r!;
          zMax = segb;
        } else {
          zMin = sega;
          zMax = fVpoint.r!;
        }
        List<FurthestPointEntry>? c = precomputedAll;
        if (c == null) {
          c = <FurthestPointEntry>[];
          flight.furthestPoints[pos][key] = c;
        }
        FurthestPointEntry? existing;
        for (final FurthestPointEntry x in c) {
          if (x.o.r == fVpoint.r && !(zMax <= x.min || zMin >= x.max)) {
            existing = x;
            break;
          }
        }
        if (existing != null) {
          existing.min = math.min(zMin, existing.min);
          existing.max = math.max(zMax, existing.max);
        } else {
          c.add(FurthestPointEntry(min: zMin, max: zMax, o: fVpoint));
        }
      }
    }

    if (distanceVMax > distanceMax) {
      distanceMax = distanceVMax;
      fpoint = fVpoint;
    }
  }
  return fpoint ?? target;
}

/// Triangle-closure check. Tries the closest-pair cache first ("fast"
/// candidates whose round-trip is already `<= closingDistanceFree`), then
/// falls back to a fresh closest-pair search. Returns the closing pair if
/// admissible under the rule, or null otherwise.
ClosingPair? isTriangleClosed(int p1, int p2, double distance, SolverOpt opt) {
  // Fast path: cached entries already covering this query.
  for (final ClosestPairEntry e in opt.flight.closestPairs) {
    if (e.minX <= opt.launch &&
        opt.launch <= e.maxX &&
        e.minY <= p2 &&
        opt.landing <= e.maxY) {
      // JS: `if (f.o.d <= opt.scoring.closingDistanceFree) return f.o;`
      final double? free = opt.scoring.closingDistanceFree;
      if (free != null && e.d <= free) {
        return ClosingPair(d: e.d, pIn: e.pIn, pOut: e.pOut);
      }
    }
  }

  final ClosestPair min = findClosestPairIn2Segments(p1, p2, opt);
  final double limit = opt.scoring.closingDistance!(distance, opt);
  if (min.d <= limit) {
    return ClosingPair(d: min.d, pIn: min.pIn!, pOut: min.pOut!);
  }
  return null;
}

/// Out-and-return closure check.
ClosingPair? isOutAndReturnClosed(
    Range rangeA, Range rangeB, double distance, SolverOpt opt) {
  final ClosestPair min = findClosestPairIn2PartialSegments(rangeA, rangeB, opt);
  final double limit = opt.scoring.closingDistance!(distance, opt);
  if (min.d <= limit) {
    return ClosingPair(d: min.d, pIn: min.pIn!, pOut: min.pOut!);
  }
  return null;
}
