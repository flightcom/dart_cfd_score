// Ported from igc-xc-score/scoring-rules.config.js (LGPL-3.0).
//
// A single rule (one flight type). The solver evaluates one `ScoringRule` at a
// time. Function fields (`bound`, `score`, `closingDistance`, `post`,
// `rounding`, `finalRounding`) are filled in by the rules config — they are
// kept as fields rather than methods so callers can swap implementations
// without subclassing, matching the JS object-literal style.

import 'foundation.dart';
import 'opt.dart';

typedef Rounding = double Function(double v);
typedef BoundFn = double Function(
    List<Range> ranges, List<Box> boxes, SolverOpt opt);
typedef ScoreFn = ScoreResult Function(List<Point> tp, SolverOpt opt);
typedef ClosingDistanceFn = double Function(double distance, SolverOpt opt);
typedef PostFn = void Function(ScoreResult score, SolverOpt opt);

/// A closing pair: two on-track points (`pIn`, `pOut`) whose round-trip
/// distance `d` is the candidate triangle/OAR closing length.
class ClosingPair {
  ClosingPair({required this.d, required this.pIn, required this.pOut});
  double d;
  Point pIn;
  Point pOut;
}

/// One leg of the scored flight (segment between two consecutive turnpoints
/// and/or endpoints).
class Leg {
  Leg({required this.name});
  final String name;
  double? d;
  Point? start;
  Point? finish;
}

/// Result of a `score` callback. `score == 0` means the candidate is not
/// admissible under the rule (e.g. FAI sides constraint violated). `tp`,
/// `cp`, `ep`, `legs`, `distance`, `penalty` are set when admissible.
class ScoreResult {
  ScoreResult({this.score = 0});
  double score;
  double? distance;
  double? penalty;
  List<Point>? tp;
  ClosingPair? cp;
  Endpoints? ep;
  List<Leg>? legs;
}

/// Open-flight endpoints (entrance / exit of the 3TP). Only set by `od` /
/// open-triangle scoring.
class Endpoints {
  Endpoints({this.start, this.finish});
  Point? start;
  Point? finish;
}

/// One scoring rule (e.g. "FFVL Triangle FAI", multiplier 1.4, minSide 0.28).
class ScoringRule {
  ScoringRule({
    required this.name,
    required this.code,
    required this.multiplier,
    required this.cardinality,
    required this.bound,
    required this.score,
    required this.rounding,
    this.finalRounding,
    this.closingDistance,
    this.closingDistanceFixed,
    this.closingDistanceFree,
    this.closingDistanceRelative,
    this.minSide,
    this.maxSide,
    this.minDistance,
    this.cylinders,
    this.post,
  });

  final String name;
  final String code; // 'od', 'tri', 'fai', 'oar'
  final double multiplier;
  final int cardinality;
  final BoundFn bound;
  final ScoreFn score;
  final Rounding rounding;
  final Rounding? finalRounding;
  final ClosingDistanceFn? closingDistance;
  final double? closingDistanceFixed;
  final double? closingDistanceFree;
  final double? closingDistanceRelative;
  final double? minSide;
  final double? maxSide;
  final double? minDistance;
  final double? cylinders;
  final PostFn? post;
}
