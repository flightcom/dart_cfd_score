import 'package:dart_cfd_score/src/flatbush.dart';
import 'package:test/test.dart';

// Reference outputs produced by the upstream JS Flatbush v3 on the same input.

void main() {
  group('Flatbush — fixed 15-point set, nodeSize=4', () {
    final List<List<int>> pts = <List<int>>[
      <int>[10, 10],
      <int>[20, 10],
      <int>[30, 10],
      <int>[10, 20],
      <int>[20, 20],
      <int>[30, 20],
      <int>[10, 30],
      <int>[20, 30],
      <int>[30, 30],
      <int>[15, 15],
      <int>[25, 25],
      <int>[5, 5],
      <int>[35, 35],
      <int>[12, 28],
      <int>[28, 12],
    ];

    Flatbush build() {
      final Flatbush idx = Flatbush(pts.length, 4);
      for (final List<int> p in pts) {
        idx.add(p[0].toDouble(), p[1].toDouble());
      }
      idx.finish();
      return idx;
    }

    test('search box [15,15]-[25,25]', () {
      final List<int> r = build().search(15, 15, 25, 25)..sort();
      expect(r, <int>[4, 9, 10]);
    });

    test('search box outside index returns empty', () {
      expect(build().search(100, 100, 110, 110), isEmpty);
    });

    // Ties at equal distance have impl-defined order (JS FlatQueue vs Dart
    // HeapPriorityQueue differ for equal-priority entries). The contract is
    // "results sorted by distance non-decreasing"; assert that.
    void expectSortedByDistanceFromQuery(
        List<int> got, double qx, double qy, List<int> expected) {
      expect(got, hasLength(expected.length));
      expect(got.toSet(), expected.toSet());
      double prev = -1;
      for (final int i in got) {
        final double dx = pts[i][0] - qx;
        final double dy = pts[i][1] - qy;
        final double d = dx * dx + dy * dy;
        expect(d, greaterThanOrEqualTo(prev));
        prev = d;
      }
    }

    test('neighbors(15,15) k=3 — point 9 first, then any 2 of the 4 tied', () {
      // Distances²: pt 9 -> 0, pts {0,1,3,4} -> 50 each. With k=3 the exact
      // pair returned among ties is impl-defined; the contract is closest-first.
      final List<int> got = build().neighbors(15, 15, maxResults: 3);
      expect(got, hasLength(3));
      expect(got.first, 9);
      expect(got.sublist(1).every((int i) => <int>{0, 1, 3, 4}.contains(i)),
          isTrue);
    });

    test('neighbors(0,0) k=5', () {
      expectSortedByDistanceFromQuery(
          build().neighbors(0, 0, maxResults: 5), 0, 0, <int>[11, 0, 9, 1, 3]);
    });

    test('neighbors(20,20) all', () {
      expectSortedByDistanceFromQuery(build().neighbors(20, 20), 20, 20,
          <int>[4, 9, 10, 3, 7, 5, 1, 13, 14, 8, 2, 0, 6, 11, 12]);
    });

    test('neighbors(15,15) k=1 returns single closest', () {
      // At (15,15), index 9 (15,15) is uniquely closest (dist 0).
      expect(build().neighbors(15, 15, maxResults: 1), <int>[9]);
    });
  });

  group('Flatbush — error handling', () {
    test('search before finish throws', () {
      final Flatbush idx = Flatbush(2);
      idx.add(0, 0);
      idx.add(1, 1);
      expect(() => idx.search(0, 0, 1, 1), throwsStateError);
    });

    test('finish without all items throws', () {
      final Flatbush idx = Flatbush(3);
      idx.add(0, 0);
      idx.add(1, 1);
      expect(idx.finish, throwsStateError);
    });

    test('neighbors before finish throws', () {
      final Flatbush idx = Flatbush(1);
      idx.add(0, 0);
      expect(() => idx.neighbors(0, 0), throwsStateError);
    });
  });

  group('Flatbush — single item', () {
    test('1 item indexes and searches', () {
      final Flatbush idx = Flatbush(1, 4);
      idx.add(5, 5);
      idx.finish();
      expect(idx.search(0, 0, 10, 10), <int>[0]);
      expect(idx.neighbors(5, 5), <int>[0]);
    });
  });
}
