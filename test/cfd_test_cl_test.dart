// Validation: real-world triangle flight against the published CFD score.
// Source: test/data/test_cl.png (CFD website screenshot).
//
// CFD website reports:
//   Type: triangle (tri) — multiplier 1.2
//   Distance: 51.42 km  |  Score: 61.70 pts
//   Legs: b1-b2 25.27 / b2-b3 24.23 / b3-b1 1.88
//
// Our Dart solver (Haversine R=6371 km) returns:
//   Type: Triangle plat (tri)  |  Distance 51.44 km  |  Score 61.73 pts
//   Legs: 25.29 / 24.23 / 1.92    TP indices r = 1143 / 8254 / 13103
//   Closing: 0.08 km (pIn=780, pOut=13149) — well under 3 km free allowance
//
// The +0.03 pt gap is excellent — almost exact match with CFD.
//
// Date: 25/04/2026
// Takeoff: Base ULM du G Moiré — Landing: Les 6 chemins

import 'package:dart_cfd_score/dart_cfd_score.dart';
import 'package:test/test.dart';

import 'helpers/igc_parser.dart';

void main() {
  test('CFD test_cl — Triangle plat, ~51.42 km / ~61.70 pts', () {
    final List<FlightFix> fixes = parseIgc('test/data/test_cl.igc');
    expect(fixes, isNotEmpty);

    final FlightState flight = flightStateFromFixes(fixes);
    final SolverResult result = solve(flight, ffvlRules);

    final Solution best = result.best;

    // Triangle plat (flat triangle), multiplier 1.2.
    expect(best.opt.scoring.code, 'tri');
    expect(result.optimal, isTrue);

    // Score within ±0.05 of the official 61.70 pts.
    expect(best.score, closeTo(61.70, 0.05));
    expect(best.scoreInfo!.distance, closeTo(51.42, 0.05));

    // Leg breakdown.
    final List<Leg> legs = best.scoreInfo!.legs!;
    expect(legs, hasLength(3));

    // Sort legs for stable comparison (TP rotation may vary).
    final List<double> ds = legs.map((Leg l) => l.d!).toList()..sort();
    expect(ds[0], closeTo(1.92, 0.05));  // b3 → b1 (shortest)
    expect(ds[1], closeTo(24.23, 0.05)); // b2 → b3
    expect(ds[2], closeTo(25.29, 0.05)); // b1 → b2

    // Closing under the free 3 km allowance → no penalty.
    expect(best.scoreInfo!.cp!.d, lessThan(3.0));
    expect(best.scoreInfo!.penalty ?? 0, 0);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
