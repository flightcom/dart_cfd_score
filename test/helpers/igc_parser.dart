// Minimal IGC B-record parser used only by validation tests. Not part of the
// public package API — the package consumes local JSON, not IGC.

import 'dart:io';

import 'package:dart_cfd_score/dart_cfd_score.dart';

/// Parse an IGC file and return one [FlightFix] per valid B record (`A` =
/// 3D fix). Timestamp is ms-since-midnight; absolute date is not needed for
/// scoring.
List<FlightFix> parseIgc(String path) {
  final List<String> lines = File(path).readAsLinesSync();
  final List<FlightFix> out = <FlightFix>[];
  for (final String l in lines) {
    if (l.length < 35 || l[0] != 'B') continue;
    // B HHMMSS DDMMmmm N/S DDDMMmmm E/W A PPPPP GGGGG ...
    final int hh = int.parse(l.substring(1, 3));
    final int mm = int.parse(l.substring(3, 5));
    final int ss = int.parse(l.substring(5, 7));
    final double latDeg = double.parse(l.substring(7, 9));
    final double latMin = double.parse(l.substring(9, 14)) / 1000;
    final String ns = l.substring(14, 15);
    final double lonDeg = double.parse(l.substring(15, 18));
    final double lonMin = double.parse(l.substring(18, 23)) / 1000;
    final String ew = l.substring(23, 24);
    final String validity = l.substring(24, 25);
    if (validity != 'A') continue;
    double lat = latDeg + latMin / 60.0;
    if (ns == 'S') lat = -lat;
    double lon = lonDeg + lonMin / 60.0;
    if (ew == 'W') lon = -lon;
    final int t = ((hh * 3600) + mm * 60 + ss) * 1000;
    out.add(FlightFix(latitude: lat, longitude: lon, timestampMs: t));
  }
  return out;
}
