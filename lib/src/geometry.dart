// Ported from igc-xc-score/src/geom.js (LGPL-3.0).
//
// Pure geometry helpers — bounding-box distance bounds used by the
// branch-and-bound solver. The spatial-search helpers (`findClosestPairIn2*`,
// `isTriangleClosed`, `isOutAndReturnClosed`) live in `spatial_search.dart`
// because they depend on the Flatbush R-tree.
//
// Reference: Ondřej Palkovský, "Paragliding Competition Tracklog Optimization"
// http://www.penguin.cz/~ondrap/algorithm.pdf — proves the maximum distance
// path between rectangles always passes through their vertices.

import 'foundation.dart';

/// Signature for a 3-arg distance function (e.g. perimeter `a→b→c`).
typedef Distance3Fn = double Function(Point a, Point b, Point c);

/// Maximum possible distance through 3 rectangles given a perimeter function
/// `distance_fn(p0, p1, p2)`. Restricts the candidate vertices using the
/// Palkovský bounding-box trick.
double maxDistance3Rectangles(List<Box> boxes, Distance3Fn distanceFn) {
  if (boxes.length != 3) {
    throw ArgumentError('maxDistance3Rectangles expects 3 boxes');
  }
  final double minx = _min3(boxes[0].x1, boxes[1].x1, boxes[2].x1);
  final double miny = _min3(boxes[0].y1, boxes[1].y1, boxes[2].y1);
  final double maxx = _max3(boxes[0].x2, boxes[1].x2, boxes[2].x2);
  final double maxy = _max3(boxes[0].y2, boxes[1].y2, boxes[2].y2);

  bool intersecting = false;
  for (int i = 0; i < 3; i++) {
    if (boxes[i].intersectsBox(boxes[(i + 1) % 3])) {
      intersecting = true;
      break;
    }
  }

  final List<List<Point>> path = <List<Point>>[<Point>[], <Point>[], <Point>[]];
  for (int i = 0; i < 3; i++) {
    final List<Point> vertices = boxes[i].vertices();
    for (final Point v in vertices) {
      if ((v.x == minx || v.x == maxx) && (v.y == miny || v.y == maxy)) {
        path[i].add(v);
      }
    }
    if (path[i].isEmpty) {
      for (final Point v in vertices) {
        if (v.x == minx || v.x == maxx || v.y == miny || v.y == maxy) {
          path[i].add(v);
        }
      }
    }
    if (path[i].isEmpty || intersecting) path[i] = vertices;
  }

  double distanceMax = 0;
  for (final Point i in path[0]) {
    for (final Point j in path[1]) {
      for (final Point k in path[2]) {
        final double d = distanceFn(i, j, k);
        if (d > distanceMax) distanceMax = d;
      }
    }
  }
  return distanceMax;
}

/// Minimum possible perimeter through 3 rectangles. Brute-force vertex search
/// (deducible from Palkovský's proof; exact and small enough — 64 combos).
double minDistance3Rectangles(List<Box> boxes, Distance3Fn distanceFn) {
  if (boxes.length != 3) {
    throw ArgumentError('minDistance3Rectangles expects 3 boxes');
  }
  final List<Point> v0 = boxes[0].vertices();
  final List<Point> v1 = boxes[1].vertices();
  final List<Point> v2 = boxes[2].vertices();

  double distanceMin = double.infinity;
  for (final Point i in v0) {
    for (final Point j in v1) {
      for (final Point k in v2) {
        final double d = distanceFn(i, j, k);
        if (d < distanceMin) distanceMin = d;
      }
    }
  }
  return distanceMin;
}

/// Minimum possible distance between 2 rectangles (vertex pair). Geometrically
/// loose vs `Box.distance` (which collapses to the minimum projected segment),
/// kept for parity with upstream `minDistance2Rectangles` API used by scoring.
double minDistance2Rectangles(List<Box> boxes) {
  if (boxes.length != 2) {
    throw ArgumentError('minDistance2Rectangles expects 2 boxes');
  }
  final List<Point> v0 = boxes[0].vertices();
  final List<Point> v1 = boxes[1].vertices();
  double distanceMin = double.infinity;
  for (final Point i in v0) {
    for (final Point j in v1) {
      final double d = i.distanceEarth(j);
      if (d < distanceMin) distanceMin = d;
    }
  }
  return distanceMin;
}

/// Maximum possible distance between 2 rectangles (vertex pair).
double maxDistance2Rectangles(List<Box> boxes) {
  if (boxes.length != 2) {
    throw ArgumentError('maxDistance2Rectangles expects 2 boxes');
  }
  final List<Point> v0 = boxes[0].vertices();
  final List<Point> v1 = boxes[1].vertices();
  double distanceMax = 0;
  for (final Point i in v0) {
    for (final Point j in v1) {
      final double d = i.distanceEarth(j);
      if (d > distanceMax) distanceMax = d;
    }
  }
  return distanceMax;
}

/// Maximum total distance across a path of vertex sets — at each "leg" the
/// caller must pick one vertex from `path[k]`. Time-critical: O(prod |path|).
/// `pathStart` lets the caller recurse without copying.
double maxDistancePath(Point? origin, List<List<Point>> path, int pathStart) {
  double distanceMax = 0;
  for (final Point i in path[pathStart]) {
    final double d1 = origin != null ? i.distanceEarth(origin) : 0;
    final double d2 =
        path.length > pathStart + 1 ? maxDistancePath(i, path, pathStart + 1) : 0;
    final double total = d1 + d2;
    if (total > distanceMax) distanceMax = total;
  }
  return distanceMax;
}

/// Either a fixed turnpoint (`Point`) or a region (`Box`). Mirrors the JS
/// `boxes` array of mixed Box/Point that `maxDistanceNRectangles` accepts.
sealed class _RectOrPoint {
  const _RectOrPoint();
  factory _RectOrPoint.from(Object o) {
    if (o is Box) return _Rect(o);
    if (o is Point) return _Pt(o);
    throw ArgumentError('boxes must contain only Box or Point, got $o');
  }
  bool intersectsAny(_RectOrPoint other);
  List<Point> vertices();
  double get minX;
  double get minY;
  double get maxX;
  double get maxY;
}

class _Rect extends _RectOrPoint {
  _Rect(this.box);
  final Box box;
  @override
  List<Point> vertices() => box.vertices();
  @override
  double get minX => box.x1;
  @override
  double get minY => box.y1;
  @override
  double get maxX => box.x2;
  @override
  double get maxY => box.y2;
  @override
  bool intersectsAny(_RectOrPoint other) => switch (other) {
        _Rect(box: final Box b) => box.intersectsBox(b),
        _Pt(point: final Point p) => box.intersectsPoint(p),
      };
}

class _Pt extends _RectOrPoint {
  _Pt(this.point);
  final Point point;
  @override
  List<Point> vertices() => <Point>[point];
  @override
  double get minX => point.x;
  @override
  double get minY => point.y;
  @override
  double get maxX => point.x;
  @override
  double get maxY => point.y;
  @override
  bool intersectsAny(_RectOrPoint other) => switch (other) {
        _Rect(box: final Box b) => b.intersectsPoint(point),
        _Pt(point: final Point p) => point.intersectsPoint(p),
      };
}

/// Maximum total path through N rectangles or fixed points. Restricts each
/// rectangle's candidate vertex set to the global-bounding-box corners (or
/// edges) when its boxes don't overlap, falling back to all four vertices when
/// they do. Mirrors the upstream `maxDistanceNRectangles` semantics.
double maxDistanceNRectangles(List<Object> rawBoxes) {
  final int n = rawBoxes.length;
  final List<_RectOrPoint> boxes = <_RectOrPoint>[
    for (final Object b in rawBoxes) _RectOrPoint.from(b),
  ];

  double minx = double.infinity;
  double miny = double.infinity;
  double maxx = double.negativeInfinity;
  double maxy = double.negativeInfinity;
  final List<List<Point>> vertices = <List<Point>>[];
  final List<List<Point>> path = <List<Point>>[];
  for (int r = 0; r < n; r++) {
    vertices.add(boxes[r].vertices());
    if (boxes[r].minX < minx) minx = boxes[r].minX;
    if (boxes[r].minY < miny) miny = boxes[r].minY;
    if (boxes[r].maxX > maxx) maxx = boxes[r].maxX;
    if (boxes[r].maxY > maxy) maxy = boxes[r].maxY;
    path.add(<Point>[]);
  }

  // "Intersecting" pairs widen the candidate vertex set — we need all four
  // corners of any box that overlaps a neighbour.
  final List<bool> intersecting = List<bool>.filled(n, false);
  for (int i = 1; i < n; i++) {
    if (boxes[i - 1].intersectsAny(boxes[i])) {
      intersecting[i - 1] = true;
      intersecting[i] = true;
    }
  }

  for (int i = 0; i < n; i++) {
    if (intersecting[i]) {
      path[i] = vertices[i];
      continue;
    }
    for (final Point v in vertices[i]) {
      if ((v.x == minx || v.x == maxx) && (v.y == miny || v.y == maxy)) {
        path[i].add(v);
      }
    }
    if (path[i].isEmpty) {
      for (final Point v in vertices[i]) {
        if (v.x == minx || v.x == maxx || v.y == miny || v.y == maxy) {
          path[i].add(v);
        }
      }
    }
    if (path[i].isEmpty) path[i] = vertices[i];
  }

  return maxDistancePath(null, path, 0);
}

double _min3(double a, double b, double c) =>
    a < b ? (a < c ? a : c) : (b < c ? b : c);
double _max3(double a, double b, double c) =>
    a > b ? (a > c ? a : c) : (b > c ? b : c);
