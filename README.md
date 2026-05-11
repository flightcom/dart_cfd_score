# dart_cfd_score

Dart port of [igc-xc-score](https://github.com/mmomtchev/igc-xc-score) — paragliding/hang-gliding flight scoring (free distance, flat triangle, FAI triangle) for the FFVL CFD and other rule sets.

Designed to be consumed by Flutter apps from raw GPS points (no IGC parser dependency).

## Status

Work in progress. Porting in stages:

- [x] Foundation (`Point`, `Range`, `Box`) + Vincenty geodesic
- [ ] Geometry helpers (max/min distance between bounding boxes)
- [ ] Flatbush R-tree port
- [ ] Scoring rules (FFVL, FAI, XContest)
- [ ] Branch-and-bound solver
- [ ] Public `solve()` API + isolate helper

## Reference scores

This port aims to match scores produced by `igc-xc-score` to within ±0.01 km on the same input. Reference traces and expected scores live in `test/reference_traces/`.

## License

LGPL-3.0-or-later, matching the upstream `igc-xc-score` license.

The Vincenty geodesic implementation is derived from [Movable Type Ltd](https://www.movable-type.co.uk/scripts/latlong-vincenty.html) (MIT).
