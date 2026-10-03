class DtConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const mapsProvider = String.fromEnvironment('MAPS_PROVIDER', defaultValue: 'osm');
  static const locationIntervalSec = 4;
}
