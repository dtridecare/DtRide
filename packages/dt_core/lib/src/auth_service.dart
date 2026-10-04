import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

/// Phone OTP + email fallback. Role is stamped into auth metadata at sign-up
/// so the DB trigger creates the right profile/driver rows.
class AuthService {
  final SupabaseClient db;
  AuthService(this.db);

  Future<void> sendPhoneOtp(String phone) =>
      db.auth.signInWithOtp(phone: phone);

  Future<AuthResponse> verifyPhoneOtp(String phone, String token) =>
      db.auth.verifyOTP(type: OtpType.sms, phone: phone, token: token);

  /// Email OTP as a 6-digit code (no redirect → GoTrue sends the Token,
  /// not just the link). Explicit shouldCreateUser so first-time
  /// rider/driver signups register instead of erroring.
  Future<void> sendEmailOtp(String email) =>
      db.auth.signInWithOtp(email: email, shouldCreateUser: true);

  Future<AuthResponse> verifyEmailOtp(String email, String token) =>
      db.auth.verifyOTP(type: OtpType.email, email: email, token: token);

  /// Ensures profile + driver rows exist (trigger normally handles this).
  /// drivers insert is ON CONFLICT DO NOTHING: self-service UPDATE on
  /// drivers is forbidden (would allow KYC self-approval), so we never
  /// attempt it — submit_kyc / decide_kyc RPCs own all writes.
  Future<DtProfile> ensureProfile(String role) async {
    final user = db.auth.currentUser;
    if (user == null) throw StateError('not signed in');
    await db.from('profiles').upsert(
        {'id': user.id, 'role': role, 'phone': user.phone});
    if (role == 'driver') {
      await db.from('drivers').upsert(
          {'id': user.id}, onConflict: 'id', ignoreDuplicates: true);
    }
    final row = await db.from('profiles').select().eq('id', user.id).single();
    return DtProfile.fromJson(row);
  }

  /// Signup details: full name (+ optional email/gender/city/referral city).
  Future<DtProfile> updateProfile({
    required String fullName,
    String? email,
    String? gender,
    String? city,
  }) async {
    final user = db.auth.currentUser;
    if (user == null) throw StateError('not signed in');
    await db.from('profiles').update({
      'full_name': fullName,
      if (email != null) 'email': email,
      if (gender != null) 'gender': gender,
      if (city != null) 'city': city,
    }).eq('id', user.id);
    final row = await db.from('profiles').select().eq('id', user.id).single();
    return DtProfile.fromJson(row);
  }

  Future<DtProfile?> currentProfile() async {
    final user = db.auth.currentUser;
    if (user == null) return null;
    final row = await db.from('profiles').select().eq('id', user.id).maybeSingle();
    return row == null ? null : DtProfile.fromJson(row);
  }

  Future<void> signOut() => db.auth.signOut();
}
