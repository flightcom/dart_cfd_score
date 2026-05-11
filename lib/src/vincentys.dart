// Ported from igc-xc-score/src/vincentys.js (LGPL-3.0).
// Original Vincenty algorithm by Movable Type Ltd (MIT):
// https://www.movable-type.co.uk/scripts/latlong-vincenty.html

import 'dart:math' as math;

import 'foundation.dart';
import 'util.dart';

class VincentyResult {
  const VincentyResult({
    required this.distance,
    required this.initialBearing,
    required this.finalBearing,
    required this.iterations,
  });

  /// Geodesic length in km.
  final double distance;

  /// Initial bearing in degrees, or NaN for coincident points.
  final double initialBearing;

  /// Final bearing in degrees, or NaN for coincident points.
  final double finalBearing;
  final int iterations;
}

/// Vincenty inverse formula. Matches upstream output (km) on the WGS84
/// ellipsoid. Throws [StateError] if the formula fails to converge.
VincentyResult inverse(Point p1, Point p2) {
  final double phi1 = radians(p1.y);
  final double lambda1 = radians(p1.x);
  final double phi2 = radians(p2.y);
  final double lambda2 = radians(p2.x);

  const double a = Wgs84.a;
  const double b = Wgs84.b;
  const double f = Wgs84.f;

  final double L = lambda2 - lambda1;
  final double tanU1 = (1 - f) * math.tan(phi1);
  final double cosU1 = 1 / math.sqrt(1 + tanU1 * tanU1);
  final double sinU1 = tanU1 * cosU1;
  final double tanU2 = (1 - f) * math.tan(phi2);
  final double cosU2 = 1 / math.sqrt(1 + tanU2 * tanU2);
  final double sinU2 = tanU2 * cosU2;

  final double sinU1sinU2 = sinU1 * sinU2;
  final double cosU1cosU2 = cosU1 * cosU2;
  final double cosU1sinU2 = cosU1 * sinU2;
  final double sinU1cosU2 = sinU1 * cosU2;

  final bool antipodal =
      L.abs() > math.pi / 2 || (phi2 - phi1).abs() > math.pi / 2;

  double lambda = L;
  double sinLambda = 0;
  double cosLambda = 0;
  double sigma = antipodal ? math.pi : 0;
  double sinSigma = 0;
  double cosSigma = antipodal ? -1 : 1;
  double sinSqSigma = 0;
  double cos2SigmaM = 1;
  double sinAlpha = 0;
  double cosSqAlpha = 1;
  double C = 0;

  double lambdaPrev;
  int iterations = 0;
  do {
    sinLambda = math.sin(lambda);
    cosLambda = math.cos(lambda);
    final double term1 = cosU2 * sinLambda;
    final double term2 = cosU1sinU2 - sinU1cosU2 * cosLambda;
    sinSqSigma = term1 * term1 + term2 * term2;
    // JS Number.EPSILON.
    if (sinSqSigma.abs() < 2.220446049250313e-16) break; // coincident/antipodal
    sinSigma = math.sqrt(sinSqSigma);
    cosSigma = sinU1sinU2 + cosU1cosU2 * cosLambda;
    sigma = math.atan2(sinSigma, cosSigma);
    sinAlpha = cosU1cosU2 * sinLambda / sinSigma;
    cosSqAlpha = 1 - sinAlpha * sinAlpha;
    cos2SigmaM = cosSqAlpha != 0 ? cosSigma - 2 * sinU1sinU2 / cosSqAlpha : 0;
    C = f / 16 * cosSqAlpha * (4 + f * (4 - 3 * cosSqAlpha));
    lambdaPrev = lambda;
    lambda = L +
        (1 - C) *
            f *
            sinAlpha *
            (sigma +
                C *
                    sinSigma *
                    (cos2SigmaM +
                        C * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)));
    final double iterationCheck =
        antipodal ? lambda.abs() - math.pi : lambda.abs();
    if (iterationCheck > math.pi) {
      throw StateError('lambda > pi');
    }
    if ((lambda - lambdaPrev).abs() <= 1e-7) break;
    iterations++;
  } while (iterations < 1000);
  if (iterations >= 1000) {
    throw StateError('Vincenty formula failed to converge');
  }

  final double uSq = cosSqAlpha * (a * a - b * b) / (b * b);
  final double A =
      1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)));
  final double B =
      uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)));
  final double deltaSigma = B *
      sinSigma *
      (cos2SigmaM +
          B /
              4 *
              (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM) -
                  B /
                      6 *
                      cos2SigmaM *
                      (-3 + 4 * sinSigma * sinSigma) *
                      (-3 + 4 * cos2SigmaM * cos2SigmaM)));

  final double s = b * A * (sigma - deltaSigma);

  final double alpha1 = sinSqSigma.abs() < 1e-300
      ? double.nan
      : math.atan2(cosU2 * sinLambda, cosU1sinU2 - sinU1cosU2 * cosLambda);
  final double alpha2 = sinSqSigma.abs() < 1e-300
      ? double.nan
      : math.atan2(cosU1 * sinLambda, -sinU1cosU2 + cosU1sinU2 * cosLambda);

  return VincentyResult(
    distance: s,
    initialBearing: s.abs() < 1e-300 ? double.nan : degrees(alpha1),
    finalBearing: s.abs() < 1e-300 ? double.nan : degrees(alpha2),
    iterations: iterations,
  );
}
