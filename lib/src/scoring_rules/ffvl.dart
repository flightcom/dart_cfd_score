// Ported from igc-xc-score/scoring-rules.config.js (LGPL-3.0) — FFVL subset.
//
// The FFVL rules drive the French CFD scoring. Three flight types are
// evaluated and the highest-scoring one wins:
//   1. Distance 3 points (open flight)        — multiplier 1.0
//   2. Triangle plat (flat triangle)          — multiplier 1.2
//   3. Triangle FAI (smallest leg ≥ 28%)      — multiplier 1.4
//
// Closing: a fixed/free allowance of 3 km plus 5% of the triangle length —
// any closing length above the free allowance is subtracted from the score.

import '../scoring.dart' as s;
import '../scoring_rule.dart';

double _round2(double v) => double.parse(v.toStringAsFixed(2));

/// FFVL scoring rules — pass to the solver to compute the CFD score for a
/// flight. The solver tries each entry and keeps the best.
final List<ScoringRule> ffvlRules = <ScoringRule>[
  ScoringRule(
    name: 'Distance 3 points',
    code: 'od',
    multiplier: 1.0,
    cardinality: 3,
    bound: s.boundDistance3Points,
    score: s.scoreDistance3Points,
    rounding: _round2,
  ),
  ScoringRule(
    name: 'Triangle plat',
    code: 'tri',
    multiplier: 1.2,
    cardinality: 3,
    bound: s.boundTriangle,
    score: s.scoreTriangle,
    closingDistance: s.closingWithLimit,
    closingDistanceFixed: 3,
    closingDistanceFree: 3,
    closingDistanceRelative: 0.05,
    rounding: _round2,
  ),
  ScoringRule(
    name: 'Triangle FAI',
    code: 'fai',
    multiplier: 1.4,
    cardinality: 3,
    bound: s.boundTriangle,
    score: s.scoreTriangle,
    minSide: 0.28,
    closingDistance: s.closingWithLimit,
    closingDistanceFixed: 3,
    closingDistanceFree: 3,
    closingDistanceRelative: 0.05,
    rounding: _round2,
  ),
];
