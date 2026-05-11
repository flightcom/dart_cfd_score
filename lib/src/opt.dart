// Solver context — equivalent of the `opt` object passed around in the JS
// source. Bundles the flight, the active scoring rule, and the [launch,
// landing] range for the current leg.

import 'flight_state.dart';
import 'scoring_rule.dart';

class SolverOpt {
  SolverOpt({
    required this.flight,
    required this.launch,
    required this.landing,
    required this.scoring,
    this.debug = false,
  });

  final FlightState flight;
  final int launch;
  final int landing;
  final ScoringRule scoring;
  final bool debug;
}
