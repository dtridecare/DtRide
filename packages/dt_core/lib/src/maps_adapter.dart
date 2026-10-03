import 'dart:convert';
import 'package:http/http.dart' as http;

/// Swap OSM -> Google/Mapbox without touching ride logic.
abstract class MapsAdapter {
  Future<({double lat, double lon, String label})> geocode(String address);
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
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': address, 'format': 'jsonv2', 'limit': '1',
    });
    final res = await _http.get(uri, headers: {'User-Agent': _ua});
    if (res.statusCode != 200) throw StateError('geocode failed: ${res.statusCode}');
    final list = jsonDecode(res.body) as List;
    if (list.isEmpty) throw StateError('address not found');
    final first = list.first as Map<String, dynamic>;
    return (
      lat: double.parse(first['lat'] as String),
      lon: double.parse(first['lon'] as String),
      label: (first['display_name'] ?? address) as String,
    );
  }

  @override
  Future<({int distM, int durS, String polyline})> route(
      double fromLat, double fromLon, double toLat, double toLon) async {
    final uri = Uri.https('router.project-osrm.org', '/route/v1/driving/$fromLon,$fromLat;$toLon,$toLat', {
      'overview': 'full', 'geometries': 'polyline',
    });
    final res = await _http.get(uri, headers: {'User-Agent': _ua});
    if (res.statusCode != 200) throw StateError('route failed: ${res.statusCode}');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = body['routes'] as List?;
    if (routes == null || routes.isEmpty) throw StateError('no route found');
    final r = routes.first as Map<String, dynamic>;
    return (
      distM: (r['distance'] as num).round(),
      durS: (r['duration'] as num).round(),
      polyline: (r['geometry'] ?? '') as String,
    );
  }
}
