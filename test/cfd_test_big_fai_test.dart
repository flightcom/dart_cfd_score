// Validation: large Triangle FAI flight (Bisanne, 7h56, ~30k fixes).
//
// CFD website reports:
//   Type: triangle FAI  |  Distance 217.06 km  |  Score 303.88 pts
//   Legs: b1-b2 60.75 / b2-b3 62.62 / b3-b1 93.56
//
// Our Dart port (Haversine `distanceEarth`, see foundation.dart) computes
// 304.04 pts / 217.17 km — 0.05 % above the CFD site, accepted by the user.
// The igc-xc-score JS reference uses the FCC polynomial which overestimates
// at mid-latitudes; it returns 304.42 pts / 217.44 km on this trace and the
// CFD site itself sits between the two. We optimize for CFD-site agreement.

import 'package:dart_cfd_score/dart_cfd_score.dart';
import 'package:test/test.dart';

import 'helpers/igc_parser.dart';

void main() {
  test('CFD test_big_fai — Triangle FAI, ~30k fixes', () {
    final List<FlightFix> fixes = parseIgc('test/data/test_big_fai.igc');
    expect(fixes, isNotEmpty);

    final FlightState flight = flightStateFromFixes(fixes);
    final SolverResult result = solve(flight, ffvlRules);

    final Solution best = result.best;
    expect(best.opt.scoring.code, 'fai');
    expect(result.optimal, isTrue);

    // Within ~0.1 % of the CFD-site score (303.88 pts / 217.06 km).
    expect(best.score, closeTo(303.88, 0.5));
    expect(best.scoreInfo!.distance, closeTo(217.06, 0.5));

    final List<double> ds = best.scoreInfo!.legs!
        .map((Leg l) => l.d!)
        .toList()
      ..sort();
    expect(ds[0], closeTo(60.75, 0.5));
    expect(ds[1], closeTo(62.62, 0.5));
    expect(ds[2], closeTo(93.56, 0.5));

    // Closing is zero (start/landing share a fix at Bisanne) → no penalty.
    expect(best.scoreInfo!.cp!.d, closeTo(0, 0.5));
    expect(best.scoreInfo!.penalty ?? 0, 0);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
