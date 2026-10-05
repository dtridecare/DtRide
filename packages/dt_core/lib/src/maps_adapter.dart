import 'dart:convert';
import 'package:http/http.dart' as http;

/// Typed map failures so UI can show actionable messages.
class GeocodeException implements Exception {
  final String kind; // 'not_found' | 'network' | 'no_route'
  final String message;
  GeocodeException(this.kind, this.message);
  @override
  String toString() => message;
}

/// Swap OSM -> Google/Mapbox without touching ride logic.
abstract class MapsAdapter {
  Future<({double lat, double lon, String label})> geocode(String address);
  Future<String> reverse(double lat, double lon);
  Future<({int distM, int durS, String polyline})> route(
      double fromLat, double fromLon, double toLat, double toLon);
}

/// Free tier: Nominatim search + public OSRM demo server.
/// Production: swap to Google/Mapbox adapter behind the same interface.
class OsmAdapter implements MapsAdapter {
  final http.Client _http;
  OsmAdapter([http.Client? client]) : _http = client ?? http.Client();

  static const _ua = 'DT-Ride/1.0 (contact: support@example.com)';

  @override
  Future<({double lat, double lon, String label})> geocode(String address) async {
    final q = address.trim();
    if (q.isEmpty) {
      throw GeocodeException('not_found', 'Type an address first.');
    }
    // Already coordinates (from map pin)? Use directly.
    final coord = RegExp(r'^(-?\d+(\.\d+)?)\s*,\s*(-?\d+(\.\d+)?)$').firstMatch(q);
    if (coord != null) {
      return (lat: double.parse(coord.group(1)!), lon: double.parse(coord.group(3)!), label: q);
    }
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': q, 'format': 'jsonv2', 'limit': '1', 'countrycodes': 'in',
    });
    try {
      final res = await _http.get(uri, headers: {'User-Agent': _ua, 'Accept-Language': 'en'}).timeout(
        const Duration(seconds: 12));
      if (res.statusCode == 403 || res.statusCode == 429) {
        throw GeocodeException('network', 'Map search is busy — wait a moment and retry.');
      }
      if (res.statusCode != 200) {
        throw GeocodeException('network', 'Map search failed (${res.statusCode}) — check connection and retry.');
      }
      final list = jsonDecode(res.body) as List;
      if (list.isEmpty) {
        throw GeocodeException('not_found',
            'Address not found — try a landmark + area (e.g. Connaught Place, Delhi). You can also tap the map to pin.');
      }
      final first = list.first as Map<String, dynamic>;
      return (
        lat: double.parse(first['lat'] as String),
        lon: double.parse(first['lon'] as String),
        label: (first['display_name'] ?? q) as String,
      );
    } on GeocodeException {
      rethrow;
    } catch (_) {
      throw GeocodeException('network', 'Map search failed — check connection and retry.');
    }
  }

  @override
  Future<String> reverse(double lat, double lon) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': '$lat', 'lon': '$lon', 'format': 'jsonv2',
    });
    try {
      final res = await _http.get(uri, headers: {'User-Agent': _ua, 'Accept-Language': 'en'}).timeout(
        const Duration(seconds: 12));
      if (res.statusCode != 200) throw StateError('${res.statusCode}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final name = (body['display_name'] ?? '') as String;
      if (name.isEmpty) throw StateError('empty');
      // Shorten: first two address parts read like a place, not coords.
      return name.split(',').take(2).join(',').trim();
    } catch (_) {
      throw GeocodeException('network', 'Could not look up this pin — address kept as coordinates.');
    }
  }

  @override
  Future<({int distM, int durS, String polyline})> route(
      double fromLat, double fromLon, double toLat, double toLon) async {
    final uri = Uri.https('router.project-osrm.org', '/route/v1/driving/$fromLon,$fromLat;$toLon,$toLat', {
      'overview': 'full', 'geometries': 'polyline',
    });
    try {
      final res = await _http.get(uri, headers: {'User-Agent': _ua}).timeout(
        const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw GeocodeException('network', 'Route failed (${res.statusCode}) — check connection and retry.');
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        throw GeocodeException('no_route', 'No driving route found between these points.');
      }
      final r = routes.first as Map<String, dynamic>;
      return (
        distM: (r['distance'] as num).round(),
        durS: (r['duration'] as num).round(),
        polyline: (r['geometry'] ?? '') as String,
      );
    } on GeocodeException {
      rethrow;
    } catch (_) {
      throw GeocodeException('network', 'Route failed — check connection and retry.');
    }
  }
}
