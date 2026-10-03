import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

/// Inbox fed by the reminders cron (low credits, expiring, blocks) + ops notes.
class NotificationService {
  final SupabaseClient db;
  NotificationService(this.db);

  String get _uid => db.auth.currentUser!.id;

  Future<List<NotificationItem>> list({int limit = 30}) async {
    final rows = await db.from('notifications').select()
        .eq('user_id', _uid).order('created_at', ascending: false).limit(limit);
    return (rows as List).map((r) => NotificationItem.fromJson(r)).toList();
  }

  Future<int> unreadCount() async {
    final rows = await db.from('notifications').select('id')
        .eq('user_id', _uid).isFilter('read_at', null).limit(100);
    return (rows as List).length;
  }

  Future<void> markAllRead() =>
      db.rpc('mark_notifications_read');
}
