import 'package:dart_cfd_score/dart_cfd_score.dart';
import 'package:test/test.dart';

// Reference values produced by running the JS upstream
// (igc-xc-score/src/foundation.js) on the same inputs.
//
// The Dart port must match these to high precision (1e-6 km == 1 mm).

void main() {
  group('Point.distanceEarthFCC', () {
    test('Paris -> London', () {
      final double d =
          Point(2.3522, 48.8566).distanceEarthFCC(Point(-0.1278, 51.5074));
      expect(d, closeTo(343.9744863337, 1e-6));
    });

    test('Chamonix -> Annecy', () {
      final double d =
          Point(6.8694, 45.9237).distanceEarthFCC(Point(6.1294, 45.8992));
      expect(d, closeTo(57.4804871402, 1e-6));
    });

    test('NYC -> LA (continental scale, FCC degrades)', () {
      final double d =
          Point(-74.0060, 40.7128).distanceEarthFCC(Point(-118.2437, 34.0522));
      expect(d, closeTo(3987.0801276865, 1e-6));
    });

    test('short hop (~135 m)', () {
      final double d = Point(6.0, 46.0).distanceEarthFCC(Point(6.001, 46.001));
      expect(d, closeTo(0.1354816972, 1e-9));
    });

    test('coincident points', () {
      expect(Point(5, 45).distanceEarthFCC(Point(5, 45)), 0);
    });

    test('symmetry', () {
      final Point a = Point(2.3, 48.8);
      final Point b = Point(-0.1, 51.5);
      expect(a.distanceEarthFCC(b), b.distanceEarthFCC(a));
    });
  });

  group('Point.distanceEarthVincentys', () {
    test('Paris -> London', () {
      final double d = Point(2.3522, 48.8566)
          .distanceEarthVincentys(Point(-0.1278, 51.5074));
      expect(d, closeTo(343.9229472801, 1e-6));
    });

    test('Chamonix -> Annecy', () {
      final double d =
          Point(6.8694, 45.9237).distanceEarthVincentys(Point(6.1294, 45.8992));
      expect(d, closeTo(57.4783989351, 1e-6));
    });

    test('NYC -> LA', () {
      final double d = Point(-74.0060, 40.7128)
          .distanceEarthVincentys(Point(-118.2437, 34.0522));
      expect(d, closeTo(3944.4222051953, 1e-6));
    });

    test('short hop', () {
      final double d =
          Point(6.0, 46.0).distanceEarthVincentys(Point(6.001, 46.001));
      expect(d, closeTo(0.1354090899, 1e-9));
    });
  });

  group('Range', () {
    test('count, center, contains', () {
      final Range r = Range(10, 20);
      expect(r.count(), 11);
      expect(r.center(), 15);
      expect(r.contains(10), isTrue);
      expect(r.contains(20), isTrue);
      expect(r.contains(21), isFalse);
      expect(r.contains(9), isFalse);
    });

    test('left/right halves cover and are disjoint', () {
      final Range r = Range(10, 20);
      final Range l = r.left();
      final Range right = r.right();
      // Mirror JS: left = [10, center], right = [start + ceil(n/2), end].
      // For [10,20]: center=15, ceil(10/2)=5 -> right.start=15.
      expect(l.start, 10);
      expect(l.end, 15);
      expect(right.start, 15);
      expect(right.end, 20);
    });

    test('right split for odd-length range matches JS', () {
      // [10,21]: end-start = 11; floor(11/2)=5 -> center=15.
      // ceil(11/2)=6 -> right.start = 16.
      final Range r = Range(10, 21);
      expect(r.center(), 15);
      expect(r.left().end, 15);
      expect(r.right().start, 16);
    });

    test('rejects inverted range', () {
      expect(() => Range(5, 4), throwsArgumentError);
    });
  });

  group('Box', () {
    test('fromRange computes tight bbox', () {
      final List<Point> pts = <Point>[
        Point(1, 2),
        Point(3, 1),
        Point(0, 4),
        Point(2, 3),
      ];
      final Box b = Box.fromRange(Range(0, 3), pts);
      expect(b.x1, 0);
      expect(b.y1, 1);
      expect(b.x2, 3);
      expect(b.y2, 4);
    });

    test('intersectsBox', () {
      final Box a = Box(0, 0, 10, 10);
      expect(a.intersectsBox(Box(5, 5, 15, 15)), isTrue);
      expect(a.intersectsBox(Box(11, 0, 20, 10)), isFalse);
      expect(a.intersectsBox(Box(0, 11, 10, 20)), isFalse);
      expect(a.intersectsBox(Box(-5, -5, 0, 0)), isTrue); // touching corner
    });

    test('intersectsPoint', () {
      final Box a = Box(0, 0, 10, 10);
      expect(a.intersectsPoint(Point(5, 5)), isTrue);
      expect(a.intersectsPoint(Point(0, 0)), isTrue);
      expect(a.intersectsPoint(Point(11, 5)), isFalse);
    });

    test('distance is 0 for overlapping boxes', () {
      expect(Box(0, 0, 10, 10).distance(Box(5, 5, 15, 15)), 0);
    });

    test('distance is positive for disjoint boxes', () {
      // Two small boxes, ~1 deg longitude apart at lat 45 ~= 78.6 km.
      final double d =
          Box(5.0, 45.0, 5.1, 45.1).distance(Box(6.0, 45.0, 6.1, 45.1));
      expect(d, greaterThan(60));
      expect(d, lessThan(80));
    });

    test('vertices order: SW, SE, NE, NW', () {
      final List<Point> v = Box(0, 0, 10, 5).vertices();
      expect(v[0].x, 0);
      expect(v[0].y, 0);
      expect(v[1].x, 10);
      expect(v[1].y, 0);
      expect(v[2].x, 10);
      expect(v[2].y, 5);
      expect(v[3].x, 0);
      expect(v[3].y, 5);
    });
  });
}
