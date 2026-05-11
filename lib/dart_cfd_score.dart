/// Public API of `dart_cfd_score` — Dart port of igc-xc-score for the FFVL
/// CFD scoring rules.
library;

export 'src/flight.dart' show FlightFix, flightStateFromFixes;
export 'src/flight_state.dart' show FlightState;
export 'src/foundation.dart' show Box, Point, Range;
export 'src/opt.dart' show SolverOpt;
export 'src/scoring_rule.dart'
    show ClosingPair, Endpoints, Leg, ScoreResult, ScoringRule;
export 'src/scoring_rules/ffvl.dart' show ffvlRules;
export 'src/solution.dart' show Solution;
export 'src/solver.dart' show SolverResult, solve;
export 'src/util.dart' show Wgs84, degrees, radians, rEarth;
export 'src/vincentys.dart' show VincentyResult, inverse;
