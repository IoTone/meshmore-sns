// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

/// Geohash precision 6, the coverage cell
/// (`meshmore-telemetry-coverage-spec.md` §7-§8, decision D8.17): about 1.2 km
/// by 610 m, the size at which "one ping per cell per hour" means "standing
/// still costs one ping an hour".
///
/// The encoding is the published base-32 interleave of longitude and latitude
/// bits. It lives here rather than as a dependency because the app needs one
/// thing from it - a stable key for a cell - and thirty lines of bit work are a
/// smaller surface than a package.
const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/// The cell key for a position: 6 characters, 30 bits, 15 per axis.
String geohash6(double lat, double lon) => geohashOf(lat, lon, 6);

/// The same encoding at another precision, for a coarser diagnostics export.
String geohashOf(double lat, double lon, int precision) {
  if (precision < 1 || precision > 12) {
    throw ArgumentError.value(precision, 'precision', 'must be 1..12');
  }
  if (lat < -90 || lat > 90) throw ArgumentError.value(lat, 'lat');
  if (lon < -180 || lon > 180) throw ArgumentError.value(lon, 'lon');

  double latLow = -90, latHigh = 90;
  double lonLow = -180, lonHigh = 180;
  final StringBuffer out = StringBuffer();
  int bit = 0;
  int ch = 0;
  bool even = true;
  while (out.length < precision) {
    if (even) {
      final double mid = (lonLow + lonHigh) / 2;
      if (lon >= mid) {
        ch = (ch << 1) | 1;
        lonLow = mid;
      } else {
        ch = ch << 1;
        lonHigh = mid;
      }
    } else {
      final double mid = (latLow + latHigh) / 2;
      if (lat >= mid) {
        ch = (ch << 1) | 1;
        latLow = mid;
      } else {
        ch = ch << 1;
        latHigh = mid;
      }
    }
    even = !even;
    bit++;
    if (bit == 5) {
      out.write(_base32[ch]);
      bit = 0;
      ch = 0;
    }
  }
  return out.toString();
}
