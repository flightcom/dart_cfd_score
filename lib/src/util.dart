// Ported from igc-xc-score/src/util.js (LGPL-3.0).

import 'dart:math' as math;

/// Mean Earth radius in km, matching upstream `REarth`.
const double rEarth = 6371;

/// WGS84 ellipsoid parameters used by the Vincenty geodesic.
class Wgs84 {
  static const double a = 6378.137; // semi-major axis (km)
  static const double b = 6356.752314245; // semi-minor axis (km)
  static const double f = 1 / 298.257223563; // flattening
}

double radians(double degrees) => degrees / (180 / math.pi);
double degrees(double radians) => radians * (180 / math.pi);
