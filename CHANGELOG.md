# Changelog

## 0.0.1 (unreleased)

- Initial scaffold.
- Port of `foundation.js` (Point, Range, Box) and `vincentys.js`.
- Port of pure geometry helpers from `geom.js` (max/min distance between
  rectangles, max-distance path, max-distance N rectangles).
- Port of the upstream `flatbush` Hilbert-packed R-tree (search by box +
  k-NN; serialization API omitted).
- Port of `geom.js` spatial-search helpers (`spatial_search.dart`):
  `findClosestPairIn2Segments`, `findClosestPairIn2PartialSegments`,
  `findFurthestPointInSegment`, `isTriangleClosed`, `isOutAndReturnClosed`.
  Closest-pair memo uses a plain list with linear filter (replacing rbush).
- Port of `scoring.js` (all bound/score functions for `od`/`tri`/`fai`/`oar`
  + `adjustFAICylinders` post-hook).
- Port of FFVL rules subset of `scoring-rules.config.js`
  (`scoring_rules/ffvl.dart`).
- Port of `solution.js` (branch-and-bound node) and `solver.js`
  (priority-queue driver). Single `solve()` entrypoint; the JS
  generator/yield-and-resume interface is collapsed.
- Local-format adapter `flight.dart` (`FlightFix`, `flightStateFromFixes`)
  replacing the IGC parser bridge.
- Smoke test exercising the full solver on a synthetic triangle.
