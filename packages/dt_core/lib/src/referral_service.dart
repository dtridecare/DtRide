import 'package:supabase_flutter/supabase_flutter.dart';

/// Referrals: every profile has an 8-char code; claiming links referee once.
/// Rewards stay pending in V1 (paid out by ops, automated in V2).
class ReferralService {
  final SupabaseClient db;
  ReferralService(this.db);

  Future<String?> myCode() async {
    final uid = db.auth.currentUser!.id;
    final row = await db.from('profiles').select('referral_code').eq('id', uid).single();
    return row['referral_code'] as String?;
  }

  Future<void> claim(String code) =>
      db.rpc('claim_referral', params: {'p_code': code});

  Future<bool> alreadyReferred() async {
    final uid = db.auth.currentUser!.id;
    final row = await db.from('referrals').select('id').eq('referee_id', uid).maybeSingle();
    return row != null;
  }
}
