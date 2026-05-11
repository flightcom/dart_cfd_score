// Ported from igc-xc-score/src/scoring.js (LGPL-3.0).
//
// Bound / score functions for each flight type. Bound functions return an
// optimistic upper bound on the score achievable with the given index ranges
// (used by the B&B solver); score functions evaluate a concrete turnpoint
// selection.

import 'foundation.dart';
import 'geometry.dart' as geom;
import 'opt.dart';
import 'scoring_rule.dart';
import 'spatial_search.dart' as ss;

// ─── closing-distance helpers ────────────────────────────────────────────

double closingPenalty(double cd, SolverOpt opt) {
  final double free = opt.scoring.closingDistanceFree ?? 0;
  return opt.scoring.rounding(cd > free ? cd : 0);
}

double closingWithLimit(double distance, SolverOpt opt) {
  final double fixed = opt.scoring.closingDistanceFixed ?? 0;
  final double rel = opt.scoring.closingDistanceRelative ?? 0;
  final double v = distance * rel;
  return opt.scoring.rounding(fixed > v ? fixed : v);
}

double closingWithPenalty(double distance, SolverOpt opt) => double.infinity;

double finalRounding(double v, SolverOpt opt) {
  if (opt.scoring.finalRounding != null) return opt.scoring.finalRounding!(v);
  return opt.scoring.rounding(v);
}

// ─── distance-3-points (open flight) ─────────────────────────────────────

double boundDistance3Points(
    List<Range> ranges, List<Box> boxes, SolverOpt opt) {
  final Object pin = ss.findFurthestPointInSegment(
      opt.launch, ranges[0].start, boxes[0], opt);
  final Object pout = ss.findFurthestPointInSegment(
      ranges[2].end, opt.landing, boxes[2], opt);
  final double maxDistance = opt.scoring.rounding(geom.maxDistanceNRectangles(
      <Object>[pin, boxes[0], boxes[1], boxes[2], pout]));
  if (maxDistance < (opt.scoring.minDistance ?? 0)) return 0;
  return finalRounding(maxDistance * opt.scoring.multiplier, opt);
}

ScoreResult scoreDistance3Points(List<Point> tp, SolverOpt opt) {
  // In score(), `target` is always a Point (a turnpoint on the track), so
  // findFurthestPointInSegment never returns a Box here — cast is safe.
  final Point pin =
      ss.findFurthestPointInSegment(opt.launch, tp[0].r!, tp[0], opt) as Point;
  final Point pout =
      ss.findFurthestPointInSegment(tp[2].r!, opt.landing, tp[2], opt) as Point;
  final List<Point> all = <Point>[pin, tp[0], tp[1], tp[2], pout];
  final List<Leg> legs = <Leg>[
    Leg(name: 'START : TP1'),
    Leg(name: 'TP1 : TP2'),
    Leg(name: 'TP2 : TP3'),
    Leg(name: 'TP3 : FINISH'),
  ];
  double distance = 0;
  for (int i = 0; i < all.length - 1; i++) {
    legs[i].d = opt.scoring.rounding(all[i].distanceEarth(all[i + 1]));
    distance += legs[i].d!;
    legs[i].start = all[i];
    legs[i].finish = all[i + 1];
  }
  distance = finalRounding(distance, opt);
  final double score = distance >= (opt.scoring.minDistance ?? 0)
      ? finalRounding(distance * opt.scoring.multiplier, opt)
      : 0;
  return ScoreResult(score: score)
    ..distance = distance
    ..tp = tp
    ..ep = Endpoints(start: pin, finish: pout)
    ..legs = legs;
}

// ─── FAI / max-side triangle constraints ─────────────────────────────────

/// Upper bound for a FAI triangle (smallest leg >= 28% of perimeter).
double _maxFAIDistance(double maxTriDistance, List<Box> boxes, SolverOpt opt) {
  final double minTriDistance =
      geom.minDistance3Rectangles(boxes, (Point i, Point j, Point k) {
    return opt.scoring.rounding(i.distanceEarth(j)) +
        opt.scoring.rounding(j.distanceEarth(k)) +
        opt.scoring.rounding(k.distanceEarth(i));
  });
  if (maxTriDistance < minTriDistance) return 0;

  final double maxAB = opt.scoring
      .rounding(geom.maxDistance2Rectangles(<Box>[boxes[0], boxes[1]]));
  final double maxBC = opt.scoring
      .rounding(geom.maxDistance2Rectangles(<Box>[boxes[1], boxes[2]]));
  final double maxCA = opt.scoring
      .rounding(geom.maxDistance2Rectangles(<Box>[boxes[2], boxes[0]]));

  final double smallestLeg = maxAB < maxBC
      ? (maxAB < maxCA ? maxAB : maxCA)
      : (maxBC < maxCA ? maxBC : maxCA);
  final double maxDistance =
      opt.scoring.rounding(smallestLeg / opt.scoring.minSide!);
  if (maxDistance < minTriDistance) return 0;
  return maxDistance < maxTriDistance ? maxDistance : maxTriDistance;
}

/// Upper bound for a flat triangle with a `maxSide` constraint.
double _maxTRIDistance(double maxTriDistance, List<Box> boxes, SolverOpt opt) {
  final double minAB = opt.scoring
      .rounding(geom.minDistance2Rectangles(<Box>[boxes[0], boxes[1]]));
  final double minBC = opt.scoring
      .rounding(geom.minDistance2Rectangles(<Box>[boxes[1], boxes[2]]));
  final double minCA = opt.scoring
      .rounding(geom.minDistance2Rectangles(<Box>[boxes[2], boxes[0]]));
  final double largestMin = minAB > minBC
      ? (minAB > minCA ? minAB : minCA)
      : (minBC > minCA ? minBC : minCA);
  final double minDistance =
      opt.scoring.rounding(largestMin / opt.scoring.maxSide!);
  if (minDistance > maxTriDistance) return 0;
  return maxTriDistance;
}

// ─── triangle (flat + FAI) ───────────────────────────────────────────────

double boundTriangle(List<Range> ranges, List<Box> boxes, SolverOpt opt) {
  final double maxTriDistance =
      geom.maxDistance3Rectangles(boxes, (Point i, Point j, Point k) {
    return opt.scoring.rounding(i.distanceEarth(j)) +
        opt.scoring.rounding(j.distanceEarth(k)) +
        opt.scoring.rounding(k.distanceEarth(i));
  });
  if (maxTriDistance < (opt.scoring.minDistance ?? 0)) return 0;

  double maxDistance = maxTriDistance;
  if (opt.scoring.minSide != null) {
    maxDistance = _maxFAIDistance(maxDistance, boxes, opt);
  }
  if (opt.scoring.maxSide != null) {
    maxDistance = _maxTRIDistance(maxDistance, boxes, opt);
  }
  if (maxDistance == 0) return 0;

  if (ranges[0].end < ranges[2].start) {
    final ClosingPair? cp =
        ss.isTriangleClosed(ranges[0].end, ranges[2].start, maxDistance, opt);
    if (cp == null) return 0;
    return finalRounding(
        (maxDistance - closingPenalty(cp.d, opt)) * opt.scoring.multiplier,
        opt);
  }
  return finalRounding(maxDistance * opt.scoring.multiplier, opt);
}

ScoreResult scoreTriangle(List<Point> tp, SolverOpt opt) {
  final List<Leg> legs = <Leg>[
    Leg(name: 'TP1 : TP2'),
    Leg(name: 'TP2 : TP3'),
    Leg(name: 'TP3 : TP1'),
  ];
  double distance = 0;
  for (int i = 0; i < tp.length; i++) {
    legs[i].d =
        opt.scoring.rounding(tp[i].distanceEarth(tp[(i + 1) % tp.length]));
    distance += legs[i].d!;
    legs[i].start = tp[i];
    legs[i].finish = tp[(i + 1) % tp.length];
  }
  distance = finalRounding(distance, opt);
  if (distance < (opt.scoring.minDistance ?? 0)) return ScoreResult(score: 0);

  if (opt.scoring.minSide != null) {
    final double minSide = opt.scoring.minSide! * distance;
    if (legs[0].d! < minSide || legs[1].d! < minSide || legs[2].d! < minSide) {
      return ScoreResult(score: 0);
    }
  }
  if (opt.scoring.maxSide != null) {
    final double maxSide = opt.scoring.maxSide! * distance;
    if (legs[0].d! > maxSide || legs[1].d! > maxSide || legs[2].d! > maxSide) {
      return ScoreResult(score: 0);
    }
  }

  final ClosingPair? cp = ss.isTriangleClosed(tp[0].r!, tp[2].r!, distance, opt);
  if (cp == null) return ScoreResult(score: 0);

  final double penalty = closingPenalty(cp.d, opt);
  final double score =
      finalRounding((distance - penalty) * opt.scoring.multiplier, opt);
  return ScoreResult(score: score)
    ..distance = distance
    ..tp = tp
    ..cp = cp
    ..legs = legs
    ..penalty = penalty;
}

// ─── out-and-return (2 TPs / XCLeague) ───────────────────────────────────

double boundOutAndReturn2(
    List<Range> ranges, List<Box> boxes, SolverOpt opt) {
  final double maxDistance =
      opt.scoring.rounding(geom.maxDistance2Rectangles(boxes)) * 2;
  if (maxDistance < (opt.scoring.minDistance ?? 0)) return 0;
  if (ranges[0].end < ranges[1].start) {
    final ClosingPair? cp =
        ss.isTriangleClosed(ranges[0].end, ranges[1].start, maxDistance, opt);
    if (cp == null) return 0;
    return finalRounding(
        (maxDistance - closingPenalty(cp.d, opt)) * opt.scoring.multiplier,
        opt);
  }
  return finalRounding(maxDistance * opt.scoring.multiplier, opt);
}

ScoreResult scoreOutAndReturn2(List<Point> tp, SolverOpt opt) {
  final double leg = opt.scoring.rounding(tp[0].distanceEarth(tp[1]));
  final double distance = finalRounding(leg * 2, opt);
  if (distance < (opt.scoring.minDistance ?? 0)) return ScoreResult(score: 0);
  final ClosingPair? cp =
      ss.isTriangleClosed(tp[0].r!, tp[1].r!, distance, opt);
  if (cp == null) return ScoreResult(score: 0);

  final double penalty = closingPenalty(cp.d, opt);
  final double score =
      finalRounding((distance - penalty) * opt.scoring.multiplier, opt);
  final List<Leg> legs = <Leg>[
    Leg(name: 'TP1 : TP2')
      ..start = tp[0]
      ..finish = tp[1]
      ..d = leg,
    Leg(name: 'TP2 : TP1')
      ..start = tp[1]
      ..finish = tp[0]
      ..d = leg,
  ];
  return ScoreResult(score: score)
    ..distance = distance
    ..tp = tp
    ..cp = cp
    ..legs = legs
    ..penalty = penalty;
}

// ─── out-and-return (1 TP / FAI) ─────────────────────────────────────────

double boundOutAndReturn1(
    List<Range> ranges, List<Box> boxes, SolverOpt opt) {
  // Merge boxes[0] and boxes[2] into the closing-line region.
  final Box box02 = Box(
    boxes[0].x1 < boxes[2].x1 ? boxes[0].x1 : boxes[2].x1,
    boxes[0].y1 < boxes[2].y1 ? boxes[0].y1 : boxes[2].y1,
    boxes[0].x2 > boxes[2].x2 ? boxes[0].x2 : boxes[2].x2,
    boxes[0].y2 > boxes[2].y2 ? boxes[0].y2 : boxes[2].y2,
  );
  final double maxDistance =
      opt.scoring.rounding(geom.maxDistance2Rectangles(<Box>[boxes[1], box02]));
  if (maxDistance < (opt.scoring.minDistance ?? 0)) return 0;

  if (ranges[0].end < ranges[2].start) {
    final ClosingPair? cp =
        ss.isOutAndReturnClosed(ranges[0], ranges[2], maxDistance, opt);
    if (cp == null) return 0;
    // Tighter bound using the median-line box.
    final Box box02m = Box(
      (boxes[0].x1 + boxes[2].x1) / 2,
      (boxes[0].y1 + boxes[2].y1) / 2,
      (boxes[0].x2 + boxes[2].x2) / 2,
      (boxes[0].y2 + boxes[2].y2) / 2,
    );
    final double realDistance = opt.scoring
        .rounding(geom.maxDistance2Rectangles(<Box>[boxes[1], box02m]));
    return finalRounding(
        (realDistance - closingPenalty(cp.d, opt)) * 2 * opt.scoring.multiplier,
        opt);
  }
  return finalRounding(maxDistance * 2 * opt.scoring.multiplier, opt);
}

ScoreResult scoreOutAndReturn1(List<Point> tp, SolverOpt opt) {
  final Point tp2 = Point((tp[0].x + tp[2].x) / 2, (tp[0].y + tp[2].y) / 2);
  final double leg = opt.scoring.rounding(tp[1].distanceEarth(tp2));
  final double distance = finalRounding(leg * 2, opt);
  if (distance < (opt.scoring.minDistance ?? 0)) return ScoreResult(score: 0);
  final double closing = opt.scoring.rounding(tp[0].distanceEarth(tp[2]));
  if (closing > opt.scoring.closingDistance!(distance, opt)) {
    return ScoreResult(score: 0);
  }
  final double penalty = closingPenalty(closing, opt);
  final double score =
      finalRounding((distance - penalty) * opt.scoring.multiplier, opt);
  final List<Leg> legs = <Leg>[
    Leg(name: 'TP1 : TP2')
      ..start = tp[1]
      ..finish = tp2
      ..d = leg,
    Leg(name: 'TP2 : TP1')
      ..start = tp2
      ..finish = tp[1]
      ..d = leg,
  ];
  return ScoreResult(score: score)
    ..distance = distance
    ..tp = <Point>[tp[1], tp2]
    ..cp = ClosingPair(d: closing, pIn: tp[0], pOut: tp[2])
    ..legs = legs;
}

// ─── FAI cylinders adjustment (post-scoring) ─────────────────────────────

/// FAI Sporting Code, Section 7D, Para 5.2.5 — move each TP by `cylinders` km
/// along the line from the centroid of its neighbours, then re-score with
/// `cylinders * 2` subtracted from each leg. Used only by the `FAI-Cylinders`
/// rules.
void adjustFAICylinders(ScoreResult score, SolverOpt opt) {
  if (score.tp == null || score.legs == null || score.score == 0) return;
  final double cyl = opt.scoring.cylinders!;

  Point moveAway(Point point, Point origin) {
    final double d0 = point.distanceEarth(origin);
    final double t = (d0 + cyl) / d0;
    return Point((1 - t) * origin.x + t * point.x,
        (1 - t) * origin.y + t * point.y);
  }

  final List<Point> tp = score.tp!;
  final List<Point?> newTP = List<Point?>.filled(tp.length, null);
  for (int i = 0; i < tp.length; i++) {
    if (tp[i].r == null) continue; // OAR second TP is already a cylinder TP
    Point previous;
    if (i == 0) {
      previous = score.ep != null ? score.ep!.start! : tp[tp.length - 1];
    } else {
      previous = tp[i - 1];
    }
    Point next;
    if (i + 1 >= tp.length) {
      next = score.ep != null ? score.ep!.finish! : tp[0];
    } else {
      next = tp[i + 1];
    }
    final Point centroid =
        Point((previous.x + next.x) / 2, (previous.y + next.y) / 2);
    newTP[i] = moveAway(tp[i], centroid);
  }
  for (int i = 0; i < tp.length; i++) {
    if (newTP[i] != null) tp[i] = newTP[i]!;
  }
  if (score.ep?.start != null) score.ep!.start = moveAway(score.ep!.start!, tp[0]);
  if (score.ep?.finish != null) {
    score.ep!.finish = moveAway(score.ep!.finish!, tp[2]);
  }

  switch (opt.scoring.code) {
    case 'tri':
    case 'fai':
      score.distance = 0;
      for (int i = 0; i < score.legs!.length; i++) {
        score.legs![i].d = opt.scoring
                .rounding(tp[i].distanceEarth(tp[(i + 1) % tp.length])) -
            cyl * 2;
        score.distance = score.distance! + score.legs![i].d!;
      }
      break;
    case 'oar':
      {
        final double d = opt.scoring.rounding(tp[0].distanceEarth(tp[1])) - cyl;
        score.legs![0].d = d;
        score.legs![1].d = d;
        score.distance = d * 2;
      }
      break;
    case 'od':
      {
        final List<Point> all = <Point>[
          score.ep!.start!,
          tp[0],
          tp[1],
          tp[2],
          score.ep!.finish!,
        ];
        score.distance = 0;
        for (int i = 0; i < all.length - 1; i++) {
          score.legs![i].d =
              opt.scoring.rounding(all[i].distanceEarth(all[i + 1])) - cyl * 2;
          score.distance = score.distance! + score.legs![i].d!;
        }
      }
      break;
  }
  score.distance = finalRounding(score.distance!, opt);
  score.score = score.distance! >= (opt.scoring.minDistance ?? 0)
      ? finalRounding(
          (score.distance! - (score.penalty ?? 0)) * opt.scoring.multiplier,
          opt)
      : 0;
}
