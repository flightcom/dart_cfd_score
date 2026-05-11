// Ported from igc-xc-score/src/solver.js (LGPL-3.0).
//
// Branch-and-bound driver. One `Solver.run()` call returns the optimal
// solution over the given scoring rules. The JS `function*` interface with
// `maxcycle` yield-and-resume is collapsed into a single iterator
// (`solveStream`) that emits the best-so-far whenever it improves, then the
// final optimal — callers wanting time-sliced execution can `.take()` the
// stream and break out.

import 'package:collection/collection.dart';

import 'flight_state.dart';
import 'foundation.dart';
import 'opt.dart';
import 'scoring_rule.dart';
import 'solution.dart';


class SolverResult {
  SolverResult({
    required this.best,
    required this.processed,
    required this.optimal,
    required this.elapsedMs,
  });
  final Solution best;
  final int processed;
  final bool optimal;
  final int elapsedMs;
}

/// Run the branch-and-bound solver over the given flight and rules. Returns
/// the highest-scoring [Solution] across all rule entries.
///
/// `maxLoops` and `maxCycleMs` bound the search; on timeout the best
/// solution found so far is returned (with `optimal == false`).
SolverResult solve(
  FlightState flight,
  List<ScoringRule> rules, {
  int? launch,
  int? landing,
  int? maxLoops,
  int? maxCycleMs,
}) {
  final int lStart = launch ?? 0;
  final int lEnd = landing ?? (flight.flightPoints.length - 1);

  // One root solution per (rule). Each root spans the full leg.
  final List<Solution> roots = <Solution>[];
  for (final ScoringRule rule in rules) {
    final SolverOpt opt = SolverOpt(
      flight: flight,
      launch: lStart,
      landing: lEnd,
      scoring: rule,
    );
    final List<Range> initRanges = List<Range>.generate(
      rule.cardinality,
      (_) => Range(lStart, lEnd),
    );
    final Solution root = Solution(initRanges, opt);
    root.doBound();
    root.doScore();
    roots.add(root);
  }

  Solution best = roots.first;
  for (final Solution r in roots) {
    if ((r.score ?? 0) > (best.score ?? 0)) best = r;
  }

  // Priority queue ordered by bound descending (highest bound popped first).
  final HeapPriorityQueue<Solution> queue = HeapPriorityQueue<Solution>(
    (Solution a, Solution b) => -Solution.contentCompare(a, b),
  );
  for (final Solution r in roots) {
    queue.add(r);
  }

  int processed = 0;
  final Stopwatch sw = Stopwatch()..start();
  bool optimal = true;

  while (queue.isNotEmpty) {
    final Solution current = queue.removeFirst();

    // Queue is bound-descending: any further pop has bound <= current.
    if ((current.bound ?? 0) <= (best.score ?? 0)) {
      queue.clear();
      break;
    }

    final List<Solution> children = current.doBranch();
    for (final Solution s in children) {
      s.doBound();
      if ((s.bound ?? 0) <= (best.score ?? 0)) continue;
      s.doScore();
      processed++;
      if ((s.score ?? 0) >= (best.score ?? 0) && (s.score ?? 0) > 0) {
        best = s;
      } else {
        // Drop the heavy scoreInfo to keep memory down — only `best` needs it.
        s.scoreInfo = null;
      }
      queue.add(s);
    }

    if (maxLoops != null && processed > maxLoops) {
      optimal = false;
      break;
    }
    if (maxCycleMs != null && sw.elapsedMilliseconds > maxCycleMs) {
      optimal = false;
      break;
    }
  }

  // Re-score the winning solution in case `scoreInfo` was dropped.
  if (best.scoreInfo == null) best.doScore();

  best.processed = processed;
  best.optimal = optimal;
  best.time = sw.elapsedMilliseconds;
  return SolverResult(
    best: best,
    processed: processed,
    optimal: optimal,
    elapsedMs: sw.elapsedMilliseconds,
  );
}

