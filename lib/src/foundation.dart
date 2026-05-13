// Ported from igc-xc-score/src/foundation.js (LGPL-3.0).

import 'dart:math' as math;

import 'util.dart';
import 'vincentys.dart' as vincentys;

/// A 2D point. By convention `x` is longitude and `y` is latitude (degrees),
/// matching upstream `igc-xc-score`. `r` is the optional fix index in the
/// originating flight track.
class Point {
  Point(this.x, this.y, {this.r});

  /// Build a point from a list of flight fixes by index.
  /// Equivalent to `new Point(fixes, i)` in the JS source.
  factory Point.fromFixes(List<Point> fixes, int i) {
    final Point p = fixes[i];
    return Point(p.x, p.y, r: i);
  }

  final double x;
  final double y;
  final int? r;

  bool intersectsPoint(Point other) => x == other.x && y == other.y;

  bool intersectsBox(Box other) => other.intersectsPoint(this);

  /// Default distance — uses the Haversine formula (R = 6371 km) to match
  /// the CFD FFVL scoring engine. Previous versions used the FCC polynomial
  /// approximation from igc-xc-score, which overestimates distances by ~0.27%
  /// at mid-latitudes.
  double distanceEarth(Point p) => distanceEarthHaversine(p);

  /// Haversine distance (km) on a sphere of mean radius 6371 km.
  /// Matches the CFD FFVL scoring engine output to sub-meter precision.
  double distanceEarthHaversine(Point p) {
    final double lat1 = radians(y);
    final double lat2 = radians(p.y);
    final double dLat = radians(p.y - y);
    final double dLon = radians(p.x - x);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    return rEarth * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// FCC polynomial distance (km). Matches upstream igc-xc-score verbatim
  /// including the cos-of-multiples speedup. Kept for reference and
  /// cross-validation, but no longer the default — the FCC formula
  /// overestimates distances by ~0.27% at 46°N latitude.
  double distanceEarthFCC(Point p) {
    final double df = p.y - y;
    final double dg = p.x - x;
    final double fm = radians((y + p.y) / 2);
    // Speed up cos computation:
    //   cos(2x) = 2 * cos(x)^2 - 1
    //   cos(a+b) = 2 * cos(a)cos(b) - cos(a-b)
    final double cosfm = math.cos(fm);
    final double cos2fm = 2 * cosfm * cosfm - 1;
    final double cos3fm = cosfm * (2 * cos2fm - 1);
    final double cos4fm = 2 * cos2fm * cos2fm - 1;
    final double cos5fm = 2 * cos2fm * cos3fm - cosfm;
    final double k1 = 111.13209 - 0.566605 * cos2fm + 0.00120 * cos4fm;
    final double k2 =
        111.41513 * cosfm - 0.09455 * cos3fm + 0.00012 * cos5fm;
    final double d =
        math.sqrt((k1 * df) * (k1 * df) + (k2 * dg) * (k2 * dg));
    return d;
  }

  /// High-precision Vincenty geodesic (km).
  double distanceEarthVincentys(Point p) => vincentys.inverse(this, p).distance;

  @override
  String toString() => 'Point($x, $y${r != null ? ', r=$r' : ''})';
}

/// An interval `[start, end]` over the flight fix array.
class Range {
  Range(this.start, this.end) {
    if (end < start) {
      throw ArgumentError('start ($start) must be <= end ($end)');
    }
  }

  final int start;
  final int end;

  int count() => end - start + 1;

  int center() => start + ((end - start) ~/ 2);

  Range left() => Range(start, center());

  /// Right half. Mirrors the JS `Math.ceil((end-start)/2)` split.
  Range right() => Range(start + ((end - start + 1) ~/ 2), end);

  bool contains(int p) => start <= p && p <= end;

  @override
  String toString() => '$start:$end';
}

/// Axis-aligned bounding box in (lon, lat) degrees.
class Box {
  Box(this.x1, this.y1, this.x2, this.y2);

  /// Tightest axis-aligned bounding box covering all fixes in [range].
  factory Box.fromRange(Range range, List<Point> flightPoints) {
    double x1 = double.infinity;
    double y1 = double.infinity;
    double x2 = double.negativeInfinity;
    double y2 = double.negativeInfinity;
    for (int i = range.start; i <= range.end; i++) {
      final Point p = flightPoints[i];
      if (p.x < x1) x1 = p.x;
      if (p.y < y1) y1 = p.y;
      if (p.x > x2) x2 = p.x;
      if (p.y > y2) y2 = p.y;
    }
    return Box(x1, y1, x2, y2);
  }

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  List<Point> vertices() => <Point>[
        Point(x1, y1),
        Point(x2, y1),
        Point(x2, y2),
        Point(x1, y2),
      ];

  bool intersectsPoint(Point other) =>
      x1 <= other.x && y1 <= other.y && x2 >= other.x && y2 >= other.y;

  bool intersectsBox(Box other) {
    if (x1 > other.x2 || x2 < other.x1 || y1 > other.y2 || y2 < other.y1) {
      return false;
    }
    return true;
  }

  double area() => ((x2 - x1) * (y2 - y1)).abs();

  /// Minimum km distance to another box (0 if intersecting). Mirrors the
  /// upstream geometry — used as an admissible lower bound during pruning.
  double distance(Box other) {
    if (intersectsBox(other)) return 0;
    double ax1 = x1, ax2 = x1, ay1 = y1, ay2 = y1;
    if (x1 > other.x2) {
      ax2 = other.x2;
    } else if (x2 < other.x1) {
      ax1 = x2;
      ax2 = other.x1;
    }
    if (y1 < other.y2) {
      ay2 = other.y2;
    } else if (y2 > other.y1) {
      ay1 = y2;
      ay2 = other.y1;
    }
    return Point(ax1, ay1).distanceEarth(Point(ax2, ay2));
  }

  @override
  String toString() => 'Box($x1, $y1, $x2, $y2)';
}
