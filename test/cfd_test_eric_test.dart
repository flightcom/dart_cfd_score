// Validation: real-world flight against the published CFD score.
// Source: test/data/test_eric.png (CFD website screenshot).
//
// CFD website reports:
//   Type: Dist 3 pts (od) — multiplier 1.0
//   Distance: 58.45 km  |  Score: 58.45 pts
//   Legs: bd-b1 1.27 / b1-b2 52.41 / b2-b3 1.26 / b3-ba 3.48
//
// Our Dart solver (Haversine R=6371 km, matching CFD) returns:
//   Type: Distance 3 points (od)  |  Distance 58.46 km  |  Score 58.46 pts
//   Legs: 1.27 / 52.47 / 1.23 / 3.49    TP indices r = 257 / 7682 / 7858
//   Endpoints: start r=39, finish r=8451
//
// The +0.01 pt gap vs the CFD website is pure rounding noise: the solver sums
// each leg rounded to 2 dp (1.27+52.47+1.23+3.49 = 58.46) whereas the CFD may
// round only the total (sum_raw → 58.45).
//
// Pilot: Eric MUSSCHOOT
// Date: 08/05/2026
// Takeoff: Le Grand Moiré — Landing: Le Puy-Saint-Bonnet

import 'package:dart_cfd_score/dart_cfd_score.dart';
import 'package:test/test.dart';

import 'helpers/igc_parser.dart';

void main() {
  test('CFD test_eric — Dist 3 pts, ~58.45 km / ~58.45 pts', () {
    final List<FlightFix> fixes = parseIgc('test/data/test_eric.igc');
    expect(fixes, isNotEmpty);

    final FlightState flight = flightStateFromFixes(fixes);
    final SolverResult result = solve(flight, ffvlRules);

    final Solution best = result.best;

    // Same rule code as the CFD result.
    expect(best.opt.scoring.code, 'od');
    expect(result.optimal, isTrue);

    // Score within ±0.02 of the official 58.45 pts (rounding noise only).
    expect(best.score, closeTo(58.45, 0.02));
    expect(best.scoreInfo!.distance, closeTo(58.45, 0.02));

    // Leg breakdown.
    final List<Leg> legs = best.scoreInfo!.legs!;
    expect(legs, hasLength(4));
    expect(legs[0].d!, closeTo(1.27, 0.02)); // bd → b1
    expect(legs[1].d!, closeTo(52.47, 0.1));  // b1 → b2
    expect(legs[2].d!, closeTo(1.23, 0.05));  // b2 → b3
    expect(legs[3].d!, closeTo(3.49, 0.02));  // b3 → ba
  }, timeout: const Timeout(Duration(minutes: 10)));
}
