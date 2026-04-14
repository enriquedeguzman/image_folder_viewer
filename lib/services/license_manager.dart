import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LicenseManager {
  static const int trialDays = 30;
  static const String _installDateKey = 'install_date';
  static const String _deviceCodeKey = 'device_code';

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    if (!prefs.containsKey(_installDateKey)) {
      await prefs.setString(
        _installDateKey,
        DateTime.now().toIso8601String(),
      );
    }

    if (!prefs.containsKey(_deviceCodeKey)) {
      await prefs.setString(_deviceCodeKey, _generateDeviceCode());
    }
  }

  static String _generateDeviceCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();

    return List.generate(
      8,
          (_) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  static Future<String> getDeviceCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deviceCodeKey) ?? 'UNKNOWN';
  }

  static Future<void> saveDeviceCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceCodeKey, code.trim().toUpperCase());
  }

  static Future<bool> isTrialExpired() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_installDateKey);
    if (raw == null || raw.trim().isEmpty) return false;

    final installDate = DateTime.tryParse(raw);
    if (installDate == null) return false;

    final start = DateTime(
      installDate.year,
      installDate.month,
      installDate.day,
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final daysUsed = today.difference(start).inDays;
    return daysUsed >= trialDays;
  }

  static Future<int> getTrialDaysLeft() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_installDateKey);
    if (raw == null || raw.trim().isEmpty) return trialDays;

    final installDate = DateTime.tryParse(raw);
    if (installDate == null) return trialDays;

    final start = DateTime(
      installDate.year,
      installDate.month,
      installDate.day,
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final daysUsed = today.difference(start).inDays;
    final daysLeft = trialDays - daysUsed;

    return daysLeft < 0 ? 0 : daysLeft;
  }

  static Future<bool> isTrialActive() async {
    final daysLeft = await getTrialDaysLeft();
    return daysLeft > 0;
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> _getSubscriptionDoc() async {
    final deviceCode = await getDeviceCode();

    return FirebaseFirestore.instance
        .collection('subscriptions')
        .doc(deviceCode)
        .get();
  }

  static Future<bool> validateKey(String key) async {
    try {
      final cleanKey = key.trim().toUpperCase();
      if (cleanKey.isEmpty) return false;

      final doc = await FirebaseFirestore.instance
          .collection('subscriptions')
          .doc(cleanKey)
          .get();

      if (!doc.exists) return false;

      final data = doc.data();
      if (data == null) return false;

      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      final expiryRaw = (data['expiry'] ?? '').toString().trim();

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

      if (DateTime.now().isAfter(expiryEndOfDay)) return false;

      await saveDeviceCode(cleanKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isPremiumActive() async {
    try {
      final doc = await _getSubscriptionDoc();
      if (!doc.exists) return false;

      final data = doc.data();
      if (data == null) return false;

      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      final expiryRaw = (data['expiry'] ?? '').toString().trim();

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
    } catch (_) {
      return false;
    }
  }

  static Future<int> getPremiumDaysLeft() async {
    try {
      final doc = await _getSubscriptionDoc();
      if (!doc.exists) return 0;

      final data = doc.data();
      if (data == null) return 0;

      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      final expiryRaw = (data['expiry'] ?? '').toString().trim();

      if (status != 'active') return 0;
      if (expiryRaw.isEmpty) return 0;

      final expiryDate = DateTime.tryParse(expiryRaw);
      if (expiryDate == null) return 0;

      final expiryEndOfDay = DateTime(
        expiryDate.year,
        expiryDate.month,
        expiryDate.day,
        23,
        59,
        59,
      );

      final now = DateTime.now();
      if (now.isAfter(expiryEndOfDay)) return 0;

      return expiryEndOfDay.difference(now).inDays + 1;
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> canUseOrganizer() async {
    if (await isPremiumActive()) return true;
    return await isTrialActive();
  }
}