// Validation: real-world FAI-triangle flight.
// Source: test/data/test2.png (CFD website screenshot).
//
// CFD website reports:
//   Type: triangle FAI  |  Distance 23.70 km  |  Score 33.19 pts
//   Legs: b1-b2 7.09 / b2-b3 7.12 / b3-b1 9.48
//
// Reference solver `igc-xc-score` (JS, FFVL rules) on the SAME .igc returns:
//   Type: Triangle FAI  |  Distance 23.83 km  |  Score 33.36 pts
//   Legs: 7.25 / 7.13 / 9.45     TP indices r = 253 / 1601 / 4296
//   Closing 1.35 km (≤ free 3 km → no penalty)
//
// Our Dart port matches the JS reference exactly (same TP indices, legs and
// score). The +0.17 pt gap vs the CFD website is between the website and the
// reference algorithm — likely the CFD runs older/heuristic code or filters
// the track before scoring. We validate against the reference, not the site.
//
// FAI constraint check (sanity): 7.13 / 23.83 = 0.299 ≥ 0.28 ✓

import 'package:dart_cfd_score/dart_cfd_score.dart';
import 'package:test/test.dart';

import 'helpers/igc_parser.dart';

void main() {
  test('CFD test2 — Triangle FAI, matches JS reference (33.36 pts)', () {
    final List<FlightFix> fixes = parseIgc('test/data/test2.igc');
    expect(fixes, isNotEmpty);

    final FlightState flight = flightStateFromFixes(fixes);
    final SolverResult result = solve(flight, ffvlRules);

    final Solution best = result.best;
    expect(best.opt.scoring.code, 'fai');
    expect(result.optimal, isTrue);

    // Exact reference match (tolerance: rounding noise only).
    expect(best.score, closeTo(33.36, 0.02));
    expect(best.scoreInfo!.distance, closeTo(23.83, 0.02));

    // Same TP indices as the JS reference solver.
    final List<int?> tpr = best.scoreInfo!.tp!
        .map((Point p) => p.r)
        .toList(growable: false);
    expect(tpr, <int>[253, 1601, 4296]);

    // Leg lengths (sort-invariant — TP1 may rotate).
    final List<double> ds = best.scoreInfo!.legs!
        .map((Leg l) => l.d!)
        .toList()
      ..sort();
    expect(ds[0], closeTo(7.13, 0.02));
    expect(ds[1], closeTo(7.25, 0.02));
    expect(ds[2], closeTo(9.45, 0.02));

    // Closing under the free 3 km allowance → no penalty applied.
    expect(best.scoreInfo!.cp!.d, closeTo(1.35, 0.02));
    expect(best.scoreInfo!.penalty ?? 0, 0);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
