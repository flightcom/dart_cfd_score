import 'package:dart_cfd_score/dart_cfd_score.dart';
import 'package:dart_cfd_score/src/geometry.dart';
import 'package:test/test.dart';

// Reference values from igc-xc-score (geom.js) on identical inputs.

double _perim3(Point a, Point b, Point c) =>
    a.distanceEarth(b) + b.distanceEarth(c) + c.distanceEarth(a);

void main() {
  // Three disjoint boxes around the Alps.
  final Box b1 = Box(6.0, 45.0, 6.5, 45.5);
  final Box b2 = Box(7.5, 46.5, 8.0, 47.0);
  final Box b3 = Box(5.0, 47.0, 5.5, 47.5);
  final Box b4 = Box(6.2, 45.2, 6.7, 45.7); // intersects b1

  group('maxDistance3Rectangles', () {
    test('disjoint boxes', () {
      expect(maxDistance3Rectangles(<Box>[b1, b2, b3], _perim3),
          closeTo(793.16738940, 1e-6));
    });

    test('intersecting pair widens candidate set', () {
      expect(maxDistance3Rectangles(<Box>[b1, b4, b2], _perim3),
          closeTo(554.28500659, 1e-6));
    });

    test('rejects non-3 input', () {
      expect(() => maxDistance3Rectangles(<Box>[b1, b2], _perim3),
          throwsArgumentError);
    });
  });

  group('minDistance3Rectangles', () {
    test('disjoint boxes', () {
      expect(minDistance3Rectangles(<Box>[b1, b2, b3], _perim3),
          closeTo(481.80413015, 1e-6));
    });
  });

  group('maxDistance2Rectangles / minDistance2Rectangles', () {
    test('max', () {
      expect(maxDistance2Rectangles(<Box>[b1, b2]),
          closeTo(270.96417599, 1e-6));
    });
    test('min', () {
      expect(minDistance2Rectangles(<Box>[b1, b2]),
          closeTo(135.48208799, 1e-6));
    });
  });

  group('maxDistanceNRectangles', () {
    test('4 boxes path', () {
      expect(maxDistanceNRectangles(<Object>[b1, b2, b3, b1]),
          closeTo(805.77967664, 1e-6));
    });

    test('mixed Box + Point', () {
      expect(
          maxDistanceNRectangles(<Object>[b1, Point(7.0, 46.0), b2]),
          closeTo(270.96324145, 1e-6));
    });

    test('rejects unknown element type', () {
      expect(() => maxDistanceNRectangles(<Object>['nope']),
          throwsArgumentError);
    });
  });

  group('maxDistancePath', () {
    test('no origin, single layer', () {
      expect(
          maxDistancePath(
              null,
              <List<Point>>[
                <Point>[Point(0, 0), Point(1, 0)],
              ],
              0),
          0);
    });

    test('two layers picks the longest pair', () {
      // Distances are FCC; just check monotonicity / pick.
      final double d = maxDistancePath(
        null,
        <List<Point>>[
          <Point>[Point(0, 45)],
          <Point>[Point(0, 45), Point(1, 45)],
        ],
        0,
      );
      expect(d, greaterThan(0));
    });
  });
}
