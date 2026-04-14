import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/license_manager.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  bool _loading = true;
  bool _premiumActive = false;
  bool _autoClosing = false;

  int _trialDaysLeft = 0;
  int _premiumDaysLeft = 0;

  String _deviceCode = '';
  String _expiryText = '-';
  String _statusText = '';

  Timer? _pollTimer;

  bool get _showExpiryWarning =>
      _premiumActive && _premiumDaysLeft > 0 && _premiumDaysLeft <= 3;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || _autoClosing) return;
      await _loadStatus(showLoader: false, autoCloseIfPremium: true);
    });
  }

  Future<void> _loadStatus({
    bool showLoader = true,
    bool autoCloseIfPremium = true,
  }) async {
    if (showLoader && mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final deviceCode = await LicenseManager.getDeviceCode();
      final trialDaysLeft = await LicenseManager.getTrialDaysLeft();
      final premiumActive = await LicenseManager.isPremiumActive();
      final premiumDaysLeft = await LicenseManager.getPremiumDaysLeft();

      String expiryText = '-';
      if (premiumActive && premiumDaysLeft > 0) {
        final expiryDate = DateTime.now().add(
          Duration(days: premiumDaysLeft - 1),
        );
        expiryText =
        '${expiryDate.year}-${expiryDate.month.toString().padLeft(2, '0')}-${expiryDate.day.toString().padLeft(2, '0')}';
      }

      if (!mounted) return;

      setState(() {
        _deviceCode = deviceCode;
        _trialDaysLeft = trialDaysLeft;
        _premiumActive = premiumActive;
        _premiumDaysLeft = premiumDaysLeft;
        _expiryText = expiryText;

        if (_premiumActive) {
          if (_showExpiryWarning) {
            _statusText =
            'Premium is active, but it will expire soon. Renew to keep Organizer active.';
          } else {
            _statusText = 'Premium is active.';
          }
        } else if (_trialDaysLeft > 0) {
          _statusText = 'Your free trial is active.';
        } else {
          _statusText =
          'Your trial has ended. Subscribe to continue using Organizer.';
        }

        _loading = false;
      });

      if (premiumActive && autoCloseIfPremium && !_autoClosing) {
        _autoClosing = true;
        _pollTimer?.cancel();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Premium activated'),
            duration: Duration(seconds: 1),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _statusText = 'Failed to load subscription status.';
      });
    }
  }

  Future<void> _copyDeviceCode() async {
    await Clipboard.setData(ClipboardData(text: _deviceCode));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Device code copied'),
      ),
    );
  }

  Future<void> _refreshPaidStatus() async {
    await _loadStatus(showLoader: true, autoCloseIfPremium: true);

    if (!mounted || _premiumActive) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No active premium found yet'),
      ),
    );
  }

  Widget _buildStatusIcon() {
    final color = _premiumActive
        ? (_showExpiryWarning
        ? const Color(0xFFD97706)
        : const Color(0xFF16A34A))
        : (_trialDaysLeft > 0
        ? const Color(0xFFD4A017)
        : const Color(0xFF2563EB));

    final icon = _premiumActive
        ? (_showExpiryWarning
        ? Icons.warning_amber_rounded
        : Icons.verified_rounded)
        : (_trialDaysLeft > 0
        ? Icons.schedule_rounded
        : Icons.lock_outline_rounded);

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(
        icon,
        color: color,
        size: 34,
      ),
    );
  }

  Widget _buildInfoCard() {
    final title = _premiumActive
        ? 'Organizer Premium Active'
        : (_trialDaysLeft > 0 ? 'Organizer Free Trial' : 'Organizer Premium');

    final subtitle = _premiumActive
        ? (_showExpiryWarning
        ? 'Your premium is still active, but renewal is needed soon.'
        : 'You can now use Organizer.')
        : (_trialDaysLeft > 0
        ? 'You still have free access to Organizer.'
        : 'Subscribe to continue using Organizer.');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFD6E4FF),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _premiumActive ? 'Premium Status' : 'Subscription',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _premiumActive ? 'Premium Active' : '₱149 / month',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: _premiumActive
                  ? (_showExpiryWarning
                  ? const Color(0xFFD97706)
                  : const Color(0xFF16A34A))
                  : const Color(0xFF2563EB),
            ),
          ),
          const SizedBox(height: 14),
          _infoRow('Device Code', _deviceCode),
          _infoRow('Trial days left', '$_trialDaysLeft'),
          _infoRow('Premium days left', '$_premiumDaysLeft'),
          _infoRow('Expiry', _expiryText),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF475569),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_premiumActive) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _showExpiryWarning
                    ? const Color(0xFFFFFBEB)
                    : const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _showExpiryWarning
                      ? const Color(0xFFFDE68A)
                      : const Color(0xFFBBF7D0),
                ),
              ),
              child: Text(
                'Expires on $_expiryText',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _showExpiryWarning
                      ? const Color(0xFF92400E)
                      : const Color(0xFF166534),
                ),
              ),
            ),
          ],
          if (_showExpiryWarning) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFD97706),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Premium expires in $_premiumDaysLeft day${_premiumDaysLeft == 1 ? '' : 's'}. Renew soon to keep Organizer active.',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_premiumActive) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context, true);
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Continue to Organizer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _showExpiryWarning
                    ? const Color(0xFFD97706)
                    : const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _copyDeviceCode,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy Device Code'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _copyDeviceCode,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy Device Code'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4B669E),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _refreshPaidStatus,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child: const Text('Check Payment Status'),
          ),
        ),
      ],
    );
  }

  Widget _buildInstructions() {
    if (_premiumActive) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _showExpiryWarning
              ? const Color(0xFFFFFBEB)
              : const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _showExpiryWarning
                ? const Color(0xFFFDE68A)
                : const Color(0xFFBBF7D0),
          ),
        ),
        child: Text(
          _showExpiryWarning
              ? 'Premium is active, but renewal is needed soon to avoid Organizer being locked.'
              : 'Premium is active on this device. You can continue using Organizer.',
          style: TextStyle(
            fontSize: 13,
            color: _showExpiryWarning
                ? const Color(0xFF92400E)
                : const Color(0xFF166534),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: const Text(
        'To activate premium, send your Device Code, GCash payment reference, and proof of payment. This page checks Firebase automatically every 5 seconds after payment.',
        style: TextStyle(
          fontSize: 13,
          color: Color(0xFF92400E),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Organizer',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: () => _loadStatus(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: const Color(0xFFE2E8F0),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildStatusIcon(),
                    const SizedBox(height: 18),
                    Text(
                      _premiumActive
                          ? 'Organizer Premium Active'
                          : 'Organizer Premium',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _statusText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF475569),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoCard(),
                    const SizedBox(height: 16),
                    _buildInstructions(),
                    const SizedBox(height: 16),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}