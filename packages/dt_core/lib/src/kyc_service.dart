import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

/// Driver KYC: doc uploads to private `kyc-docs/<uid>/...` bucket,
/// then submit_kyc RPC upserts vehicle + resets status to pending.
class KycService {
  final SupabaseClient db;
  KycService(this.db);

  String get _uid => db.auth.currentUser!.id;

  Future<String> uploadDoc(Uint8List bytes, String fileName) async {
    final path = '$_uid/$fileName';
    await db.storage.from('kyc-docs').uploadBinary(
        path, bytes,
        fileOptions: const FileOptions(upsert: true));
    return path;
  }

  Future<void> submit({
    required String category,
    required String upiId,
    required String plate,
    String? make,
    String? model,
    String? licenceNo,
    String? licenceExpiry,
  }) async {
    await db.rpc('submit_kyc', params: {
      'p_category': category,
      'p_upi': upiId,
      'p_plate': plate,
      'p_make': make,
      'p_model': model,
      if (licenceNo != null) 'p_licence_no': licenceNo,
      if (licenceExpiry != null) 'p_licence_expiry': licenceExpiry,
    });
  }

  /// Rider selfie + ID submitted (files uploaded to kyc-docs first).
  Future<void> submitRiderKyc() =>
      db.rpc('submit_rider_kyc');

  /// Counterparty card for a ride (name/rating/trips/vehicle, no PII).
  Future<Map<String, dynamic>> partyCard(String rideId) async {
    final res = await db.rpc('ride_party_public', params: {'p_ride': rideId});
    return Map<String, dynamic>.from(res as Map);
  }

  Future<DriverKyc> getKyc() async {
    final row = await db.from('drivers').select().eq('id', _uid).single();
    return DriverKyc.fromJson(row);
  }

  /// True once the driver has submitted at least one vehicle (distinguishes
  /// fresh accounts from pending review, since kyc_status defaults pending).
  Future<bool> hasSubmission() async {
    final rows = await db.from('vehicles').select('id').eq('driver_id', _uid).limit(1);
    return (rows as List).isNotEmpty;
  }

  Stream<DriverKyc> watchKyc() => db
      .from('drivers')
      .stream(primaryKey: ['id'])
      .eq('id', _uid)
      .map((rows) => DriverKyc.fromJson(
          rows.firstWhere((r) => r['id'] == _uid)));
}
