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
  }) async {
    await db.rpc('submit_kyc', params: {
      'p_category': category,
      'p_upi': upiId,
      'p_plate': plate,
      'p_make': make,
      'p_model': model,
    });
  }

  Future<DriverKyc> getKyc() async {
    final row = await db.from('drivers').select().eq('id', _uid).single();
    return DriverKyc.fromJson(row);
  }

  Stream<DriverKyc> watchKyc() => db
      .from('drivers')
      .stream(primaryKey: ['id'])
      .eq('id', _uid)
      .map((rows) => DriverKyc.fromJson(
          rows.firstWhere((r) => r['id'] == _uid)));
}
