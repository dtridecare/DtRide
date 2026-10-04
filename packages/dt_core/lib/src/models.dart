enum RideStatus {
  requested, accepted, arrived, started, completed,
  cancelledBeforeOtp, cancelledAfterStart, noDriverFound
}

RideStatus rideStatusFromDb(String s) => switch (s) {
  'requested' => RideStatus.requested,
  'accepted' => RideStatus.accepted,
  'arrived' => RideStatus.arrived,
  'started' => RideStatus.started,
  'completed' => RideStatus.completed,
  'cancelled_before_otp' => RideStatus.cancelledBeforeOtp,
  'cancelled_after_start' => RideStatus.cancelledAfterStart,
  'no_driver_found' => RideStatus.noDriverFound,
  _ => RideStatus.requested,
};

class Ride {
  final String id; final RideStatus status;
  final String category; final String mode;
  final String? pickupText; final String? dropText;
  final int? fareEstimateRs; final int? proposedFareRs;
  final String? driverId; final DateTime? createdAt;
  const Ride({required this.id, required this.status, required this.category,
    required this.mode, this.pickupText, this.dropText,
    this.fareEstimateRs, this.proposedFareRs, this.driverId, this.createdAt});
  factory Ride.fromJson(Map<String, dynamic> j) => Ride(
    id: j['id'] as String,
    status: rideStatusFromDb(j['status'] as String? ?? 'requested'),
    category: (j['category'] ?? 'Mini') as String,
    mode: (j['mode'] ?? 'fixed') as String,
    pickupText: j['pickup_text'] as String?,
    dropText: j['drop_text'] as String?,
    fareEstimateRs: j['fare_estimate_rs'] as int?,
    proposedFareRs: j['proposed_fare_rs'] as int?,
    driverId: j['driver_id'] as String?,
    createdAt: j['created_at'] == null ? null : DateTime.tryParse(j['created_at'] as String),
  );
}

class DtProfile {
  final String id; final String role;
  final String? phone; final String? fullName; final bool isAdmin;
  final String riderKycStatus; final String? riderKycNote;
  final String? email; final String? gender; final String? city;
  const DtProfile({required this.id, required this.role, this.phone,
    this.fullName, this.isAdmin = false,
    this.riderKycStatus = 'not_submitted', this.riderKycNote,
    this.email, this.gender, this.city});
  factory DtProfile.fromJson(Map<String, dynamic> j) => DtProfile(
    id: j['id'] as String, role: (j['role'] ?? 'rider') as String,
    phone: j['phone'] as String?, fullName: j['full_name'] as String?,
    isAdmin: (j['is_admin'] ?? false) as bool,
    riderKycStatus: (j['rider_kyc_status'] ?? 'not_submitted') as String,
    riderKycNote: j['rider_kyc_note'] as String?,
    email: j['email'] as String?,
    gender: j['gender'] as String?,
    city: j['city'] as String?,
  );
}

class DriverKyc {
  final String kycStatus; final String? notes;
  final String vehicleCategory; final String? upiId;
  final bool online; final int strikes; final DateTime? blockedUntil;
  const DriverKyc({required this.kycStatus, this.notes, required this.vehicleCategory,
    this.upiId, this.online = false, this.strikes = 0, this.blockedUntil});
  factory DriverKyc.fromJson(Map<String, dynamic> j) => DriverKyc(
    kycStatus: (j['kyc_status'] ?? 'pending') as String,
    notes: j['kyc_notes'] as String?,
    vehicleCategory: (j['vehicle_category'] ?? 'Mini') as String,
    upiId: j['upi_id'] as String?,
    online: (j['online'] ?? false) as bool,
    strikes: (j['strikes'] ?? 0) as int,
    blockedUntil: j['blocked_until'] == null
        ? null : DateTime.tryParse(j['blocked_until'] as String),
  );
  bool get approved => kycStatus == 'approved';
  bool get blocked => blockedUntil != null && DateTime.now().isBefore(blockedUntil!);
}

class SubscriptionPlan {
  final String id; final String name; final String category;
  final int rideCredits; final int priceRs; final int validityDays;
  const SubscriptionPlan({required this.id, required this.name, required this.category,
    required this.rideCredits, required this.priceRs, required this.validityDays});
  factory SubscriptionPlan.fromJson(Map<String, dynamic> j) => SubscriptionPlan(
    id: j['id'] as String, name: j['name'] as String,
    category: (j['vehicle_category'] ?? 'Mini') as String,
    rideCredits: (j['ride_credits'] ?? 0) as int,
    priceRs: (j['price_rs'] ?? 0) as int,
    validityDays: (j['validity_days'] ?? 30) as int,
  );
}

class DriverSubscription {
  final String id; final String status;
  final int total; final int used;
  final DateTime expiresAt;
  const DriverSubscription({required this.id, required this.status,
    required this.total, required this.used, required this.expiresAt});
  factory DriverSubscription.fromJson(Map<String, dynamic> j) => DriverSubscription(
    id: j['id'] as String, status: (j['status'] ?? 'pending') as String,
    total: (j['credits_total'] ?? 0) as int,
    used: (j['credits_used'] ?? 0) as int,
    expiresAt: DateTime.parse(j['expires_at'] as String),
  );
  int get remaining => total - used;
  bool get usable => status == 'active' && remaining > 0 && DateTime.now().isBefore(expiresAt);
}

class RideOffer {
  final String id; final String driverId;
  final int amountRs; final int round; final String status;
  const RideOffer({required this.id, required this.driverId,
    required this.amountRs, required this.round, required this.status});
  factory RideOffer.fromJson(Map<String, dynamic> j) => RideOffer(
    id: j['id'] as String, driverId: j['driver_id'] as String,
    amountRs: (j['amount_rs'] ?? 0) as int,
    round: (j['round'] ?? 1) as int,
    status: (j['status'] ?? 'pending') as String,
  );
}

class NearbyRequest {
  final String rideId; final String category; final String mode;
  final int fareEstimate; final int? proposedFare;
  final int distanceM; final String? pickupText; final String? dropText;
  final double pickupLon; final double pickupLat; final int distM;
  const NearbyRequest({required this.rideId, required this.category, required this.mode,
    required this.fareEstimate, this.proposedFare, required this.distanceM,
    this.pickupText, this.dropText,
    required this.pickupLon, required this.pickupLat, required this.distM});
  factory NearbyRequest.fromJson(Map<String, dynamic> j) => NearbyRequest(
    rideId: j['ride_id'] as String,
    category: (j['category'] ?? 'Mini') as String,
    mode: (j['mode'] ?? 'fixed') as String,
    fareEstimate: (j['fare_estimate'] ?? 0) as int,
    proposedFare: j['proposed_fare'] as int?,
    distanceM: (j['distance_m'] ?? 0) as int,
    pickupText: j['pickup_text'] as String?,
    dropText: j['drop_text'] as String?,
    pickupLon: (j['pickup_lon'] as num).toDouble(),
    pickupLat: (j['pickup_lat'] as num).toDouble(),
    distM: (j['dist_m'] ?? 0) as int,
  );
}

class FareQuote {
  final int distanceM; final int durationS; final int fareRs;
  const FareQuote({required this.distanceM, required this.durationS, required this.fareRs});
}

class Coupon {
  final String code; final int discountRs;
  const Coupon({required this.code, required this.discountRs});
  factory Coupon.fromJson(Map<String, dynamic> j) => Coupon(
    code: j['code'] as String, discountRs: (j['discount_rs'] ?? 0) as int);
}

class NotificationItem {
  final String id; final String title; final String body;
  final String kind; final bool read;
  final DateTime createdAt;
  const NotificationItem({required this.id, required this.title, required this.body,
    required this.kind, required this.read, required this.createdAt});
  factory NotificationItem.fromJson(Map<String, dynamic> j) => NotificationItem(
    id: j['id'] as String,
    title: (j['title'] ?? '') as String,
    body: (j['body'] ?? '') as String,
    kind: (j['kind'] ?? 'info') as String,
    read: j['read_at'] != null,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

