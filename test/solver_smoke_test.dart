// Smoke test: run the full solver on a synthetic FAI-shaped trace and assert
// the result is sane (positive score, triangle wins over open distance).
// Reference values are NOT compared against the JS implementation here — that
// will come in a separate validation suite.

import 'package:dart_cfd_score/dart_cfd_score.dart';
import 'package:test/test.dart';

void main() {
  group('Solver — synthetic FAI-ish triangle', () {
    // Three corners forming a near-equilateral triangle around Annecy, France
    // (~25 km legs). Closes back near the start so triangle scoring applies.
    final List<List<double>> corners = <List<double>>[
      <double>[6.150, 45.900], // launch / closing
      <double>[6.420, 46.000], // TP2  (~25 km east-NE)
      <double>[6.150, 46.130], // TP3  (~25 km north)
      <double>[6.150, 45.910], // closing point (near launch)
    ];

    // Build a dense polyline along the triangle edges. Timestamps must be
    // strictly monotonic — `flightStateFromFixes` deduplicates consecutive
    // identical timestamps (matches igc-xc-score `flight.filtered`).
    int t = 0;
    List<FlightFix> traceLeg(List<double> a, List<double> b, int steps) {
      final List<FlightFix> out = <FlightFix>[];
      for (int i = 0; i < steps; i++) {
        final double f = i / steps;
        out.add(FlightFix(
          longitude: a[0] + (b[0] - a[0]) * f,
          latitude: a[1] + (b[1] - a[1]) * f,
          timestampMs: t++,
        ));
      }
      return out;
    }

    final List<FlightFix> fixes = <FlightFix>[
      ...traceLeg(corners[0], corners[1], 40),
      ...traceLeg(corners[1], corners[2], 40),
      ...traceLeg(corners[2], corners[3], 40),
      FlightFix(
          longitude: corners[3][0],
          latitude: corners[3][1],
          timestampMs: t),
    ];

    test('solver returns a positive score and an optimal solution', () {
      final FlightState flight = flightStateFromFixes(fixes);
      final SolverResult result = solve(flight, ffvlRules);

      expect(result.best.score, isNotNull);
      expect(result.best.score!, greaterThan(0));
      expect(result.optimal, isTrue);
      expect(result.best.scoreInfo, isNotNull);
      expect(result.best.scoreInfo!.distance, isNotNull);
      // ~75 km perimeter * 1.4 multiplier ≈ ~105 pts upper bound.
      expect(result.best.scoreInfo!.distance!, inInclusiveRange(60.0, 80.0));
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
