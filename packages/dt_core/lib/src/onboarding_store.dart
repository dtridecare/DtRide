import 'package:shared_preferences/shared_preferences.dart';

/// First-launch onboarding flag, one key per app.
class OnboardingStore {
  final String key;
  OnboardingStore(this.key);

  Future<bool> seen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }
}
