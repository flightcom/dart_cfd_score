// Ported from igc-xc-score/src/solution.js (LGPL-3.0).
//
// A node of the branch-and-bound tree. Holds one candidate `[range × range ×
// ...]` slice of the flight; `do_bound()` computes an optimistic upper bound,
// `do_score()` computes the achievable score with the range midpoints, and
// `do_branch()` produces two children by splitting the widest range.
//
// The GeoJSON emitter (debug/visualization) from the JS source is omitted.

import 'foundation.dart';
import 'opt.dart';
import 'scoring_rule.dart';

int _idCounter = 0;

class Solution {
  Solution(List<Range> ranges, this.opt, [this.parent])
      : id = _idCounter++,
        ranges = List<Range>.from(
            ranges.length > opt.scoring.cardinality
                ? ranges.sublist(0, opt.scoring.cardinality)
                : ranges) {
    // Left-first canonicalization: enforce non-decreasing range starts and
    // non-decreasing range ends. Turns permutations into combinations, cutting
    // the search space dramatically.
    for (int r = 0; r < this.ranges.length; r++) {
      if (r > 0 && this.ranges[r - 1].start > this.ranges[r].start) {
        this.ranges[r] = Range(this.ranges[r - 1].start, this.ranges[r].end);
      }
      if (r < this.ranges.length - 1 &&
          this.ranges[r].end > this.ranges[r + 1].end) {
        this.ranges[r] = Range(this.ranges[r].start, this.ranges[r + 1].end);
      }
      boxes.add(Box.fromRange(this.ranges[r], opt.flight.flightPoints));
    }
  }

  final int id;
  final SolverOpt opt;
  final List<Range> ranges;
  final List<Box> boxes = <Box>[];
  final Solution? parent;

  double? score;
  double? bound;
  ScoreResult? scoreInfo;

  // Filled in by the solver before yielding the best solution.
  int? processed;
  bool? optimal;
  double? currentUpperBound;
  int? time;

  /// Branch on the widest range. Returns 0 or 2 children.
  List<Solution> doBranch() {
    int div = 0;
    // Breadth-first preference: split the range with the most fixes...
    for (int r = 0; r < ranges.length; r++) {
      if (ranges[r].count() > ranges[div].count()) div = r;
    }
    // ...then bias toward boxes that are pathologically larger than the
    // current divisor's box (helps early prune of impossible branches).
    for (int r = 0; r < ranges.length; r++) {
      if (ranges[r].count() > 1 && boxes[r].area() > boxes[div].area() * 8) {
        div = r;
      }
    }
    if (ranges[div].count() == 1) return const <Solution>[];

    final List<Solution> sub = <Solution>[];
    for (final Range i in <Range>[ranges[div].left(), ranges[div].right()]) {
      final List<Range> subRanges = <Range>[];
      for (int r = 0; r < ranges.length; r++) {
        subRanges.add(r == div ? i : ranges[r]);
      }
      sub.add(Solution(subRanges, opt, this));
    }
    return sub;
  }

  void doBound() {
    bound = opt.scoring.bound(ranges, boxes, opt);
  }

  void doScore() {
    // Centers must be strictly increasing — same TP can't be picked twice.
    for (int r = 0; r < ranges.length - 1; r++) {
      if (ranges[r].center() >= ranges[r + 1].center()) {
        score = 0;
        return;
      }
    }
    final List<Point> tp = <Point>[
      for (int r = 0; r < ranges.length; r++)
        Point.fromFixes(opt.flight.flightPoints, ranges[r].center()),
    ];
    scoreInfo = opt.scoring.score(tp, opt);
    if (opt.scoring.post != null) opt.scoring.post!(scoreInfo!, opt);
    score = scoreInfo!.score;
  }

  /// Sort key for the B&B priority queue: highest bound first, tie-break by
  /// insertion id (stable).
  static int contentCompare(Solution a, Solution b) {
    final double ab = a.bound ?? double.negativeInfinity;
    final double bb = b.bound ?? double.negativeInfinity;
    if (ab < bb) return -1;
    if (ab > bb) return 1;
    if (a.id < b.id) return -1;
    if (a.id > b.id) return 1;
    return 0;
  }

  @override
  String toString() {
    final StringBuffer sb = StringBuffer(opt.scoring.name);
    if (score != null && score != 0) sb.write(' $score points');
    if (scoreInfo?.distance != null) {
      sb.write(' ${scoreInfo!.distance!.toStringAsFixed(2)}km');
    }
    if (bound != null) sb.write(' ( <${bound!.toStringAsFixed(2)} )');
    return sb.toString();
  }
}
