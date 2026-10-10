import 'package:supabase_flutter/supabase_flutter.dart';

class EmergencyContact {
  final String id; final String name; final String phone;
  const EmergencyContact({required this.id, required this.name, required this.phone});
  factory EmergencyContact.fromJson(Map<String, dynamic> j) => EmergencyContact(
    id: j['id'] as String,
    name: (j['name'] ?? '') as String,
    phone: (j['phone'] ?? '') as String,
  );
}

class SupportTicket {
  final String id; final String subject;
  final String? body; final String status;
  final String? rideId; final DateTime createdAt;
  const SupportTicket({required this.id, required this.subject, this.body,
    required this.status, this.rideId, required this.createdAt});
  factory SupportTicket.fromJson(Map<String, dynamic> j) => SupportTicket(
    id: j['id'] as String,
    subject: (j['subject'] ?? '') as String,
    body: j['body'] as String?,
    status: (j['status'] ?? 'open') as String,
    rideId: j['ride_id'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

/// Emergency contacts + support tickets (both apps).
class CareService {
  final SupabaseClient db;
  CareService(this.db);

  String get _uid => db.auth.currentUser!.id;

  Future<List<EmergencyContact>> contacts() async {
    final rows = await db.from('emergency_contacts').select()
        .eq('user_id', _uid).order('created_at');
    return (rows as List).map((r) => EmergencyContact.fromJson(r)).toList();
  }

  Future<void> addContact(String name, String phone) async {
    await db.from('emergency_contacts')
        .insert({'user_id': _uid, 'name': name.trim(), 'phone': phone.trim()});
  }

  Future<void> deleteContact(String id) async {
    await db.from('emergency_contacts').delete().eq('id', id).eq('user_id', _uid);
  }

  Future<List<SupportTicket>> tickets() async {
    final rows = await db.from('support_tickets').select()
        .eq('user_id', _uid).order('created_at', ascending: false).limit(30);
    return (rows as List).map((r) => SupportTicket.fromJson(r)).toList();
  }

  Future<void> openTicket({required String subject, String? body, String? rideId}) async {
    await db.from('support_tickets').insert({
      'user_id': _uid, 'subject': subject.trim(),
      if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
      if (rideId != null) 'ride_id': rideId,
    });
  }
}
