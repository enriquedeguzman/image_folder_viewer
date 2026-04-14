import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class SubscriptionService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<bool> isSubscribed(String deviceCode) async {
    try {
      final code = deviceCode.trim();
      if (code.isEmpty) return false;

      final doc = await _db.collection('subscriptions').doc(code).get();

      if (!doc.exists) {
        debugPrint('No Firebase subscription found for device code: $code');
        return false;
      }

      final data = doc.data();
      if (data == null) return false;

      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      final expiryRaw = (data['expiry'] ?? '').toString().trim();

      debugPrint('Firebase status: $status');
      debugPrint('Firebase expiry: $expiryRaw');

      if (status != 'active') return false;
      if (expiryRaw.isEmpty) return false;

      final expiryDate = DateTime.tryParse(expiryRaw);
      if (expiryDate == null) return false;

      final expiryEndOfDay = DateTime(
        expiryDate.year,
        expiryDate.month,
        expiryDate.day,
        23,
        59,
        59,
      );

      return !DateTime.now().isAfter(expiryEndOfDay);
    } catch (e) {
      debugPrint('Subscription check failed: $e');
      return false;
    }
  }
}