// All user-facing copy. English for V1; add `hi` map with identical keys for Hindi.
import 'package:flutter/material.dart';

abstract final class Str {
  // Auth
  static const welcomeBack = 'Welcome back';
  static const riderTagline = 'Rides at fair fares, paid directly to your driver.';
  static const driverTagline = 'Keep 100% of every fare. Just a flat plan.';
  static const phoneLabel = 'Phone number';
  static const phoneHint = '+91…';
  static const sendOtp = 'Send OTP';
  static const otpLabel = 'Enter OTP';
  static const verifyOtp = 'Verify & continue';
  static const resendOtp = 'Resend code';

  // Booking
  static const whereTo = 'Where to?';
  static const pickupHint = 'Pickup location';
  static const dropHint = 'Drop location';
  static const useCurrent = 'Use current location';
  static const getFare = 'Get fare estimate';
  static const requestRide = 'Request ride';
  static const fixedFare = 'Fixed';
  static const bidFare = 'Bid';
  static const couponHint = 'Coupon (optional)';
  static const apply = 'Apply';
  static const payDirect = 'Pay driver directly (cash/UPI)';

  // Tracking
  static const shareOtp = 'Share this OTP with your driver';
  static const cancelRide = 'Cancel ride';
  static const sos = 'SOS';
  static const emergencyCall = 'Emergency call 112';
  static const rateDriver = 'Rate your driver';

  // Driver
  static const goOnline = 'Go online';
  static const goOffline = 'Go offline';
  static const buyPlan = 'Buy / renew plan';
  static const viewRequests = 'View ride requests';
  static const arrived = "I've arrived";
  static const startRide = 'Start ride';
  static const endRide = 'End ride';

  // Common
  static const retry = 'Retry';
  static const close = 'Close';
  static const loading = 'Loading…';
}

/// Vehicle categories with display metadata.
class VehicleCategory {
  final String id; final String label; final IconData icon;
  final int etaMin; final int seats;
  const VehicleCategory(this.id, this.label, this.icon, this.etaMin, this.seats);
  static const all = [
    VehicleCategory('Bike', 'Bike', Icons.two_wheeler, 2, 1),
    VehicleCategory('Auto', 'Auto', Icons.electric_rickshaw, 3, 3),
    VehicleCategory('Mini', 'Cab', Icons.directions_car, 4, 4),
    VehicleCategory('Sedan', 'Sedan', Icons.local_taxi, 5, 4),
    VehicleCategory('SUV', 'SUV', Icons.airport_shuttle, 7, 6),
  ];
}
