import 'package:flutter/material.dart';

import '../../services/license_manager.dart';
import '../../services/report_service.dart';
import '../activation/subscription_page.dart';
import '../organizer/organizer_page.dart';

class MonthlySalesPoint {
  final DateTime month;
  final double total;

  const MonthlySalesPoint({
    required this.month,
    required this.total,
  });
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const Color _blue = Color(0xFF2F6FD6);
  static const Color _blueSoft = Color(0xFFDCEBFF);

  static const Color _gold = Color(0xFFD4A017);
  static const Color _goldSoft = Color(0xFFFFF4CC);

  static const Color _green = Color(0xFF16A34A);
  static const Color _greenSoft = Color(0xFFDCFCE7);

  bool _loading = true;
  bool _isCleanMode = false;

  bool _premiumActive = false;
  int _premiumDaysLeft = 0;

  int _trialDaysLeft = 0;
  bool _trialActive = false;

  double _weeklyTotal = 0;
  double _monthlyTotal = 0;
  double _yearlyTotal = 0;

  int _weeklyCount = 0;
  int _monthlyCount = 0;
  int _yearlyCount = 0;

  String _weekRange = '';
  String _monthRange = '';
  String _yearRange = '';

  List<MonthlySalesPoint> _monthlyTrend = [];
  TopCustomerStat? _topCustomer;
  TopProductStat? _topProduct;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  String _formatShortDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  String _formatMonthYear(DateTime d) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  String _peso(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = parts[0];
    final decimal = parts[1];

    final negative = whole.startsWith('-');
    final digits = negative ? whole.substring(1) : whole;

    final chars = digits.split('').reversed.toList();
    final grouped = <String>[];

    for (int i = 0; i < chars.length; i++) {
      grouped.add(chars[i]);
      if ((i + 1) % 3 == 0 && i != chars.length - 1) {
        grouped.add(',');
      }
    }

    final resultWhole = grouped.reversed.join();
    return '${negative ? '-' : ''}₱$resultWhole.$decimal';
  }

  List<MonthlySalesPoint> _buildMonthlyTrend(List<dynamic> orders) {
    final now = DateTime.now();
    final map = <String, double>{};

    for (int i = 11; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      map[key] = 0;
    }

    for (final order in orders) {
      DateTime? dt;
      double total = 0;

      try {
        dt = DateTime.tryParse(order.dateIso);
      } catch (_) {}

      try {
        total = (order.finalTotal as num).toDouble();
      } catch (_) {}

      if (dt == null) continue;

      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      if (!map.containsKey(key)) continue;

      map[key] = (map[key] ?? 0) + total;
    }

    final result = map.entries.map((e) {
      final parts = e.key.split('-');
      return MonthlySalesPoint(
        month: DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          1,
        ),
        total: e.value,
      );
    }).toList();

    result.sort((a, b) => a.month.compareTo(b.month));
    return result;
  }

  Future<void> _openOrganizerOrSubscription() async {
    final allowed = await LicenseManager.canUseOrganizer();

    if (!mounted) return;

    if (allowed) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const OrganizerPage(),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const SubscriptionPage(),
        ),
      );
    }

    if (!mounted) return;
    _loadDashboard();
  }

  Future<void> _openSubscriptionPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SubscriptionPage(),
      ),
    );

    if (!mounted) return;
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() => _loading = true);

    try {
      final analytics = await ReportService.loadDashboardAnalytics();
      final premiumActive = await LicenseManager.isPremiumActive();
      final premiumDays = await LicenseManager.getPremiumDaysLeft();
      final trialDays = await LicenseManager.getTrialDaysLeft();
      final trialActive = await LicenseManager.isTrialActive();

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 6));
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0);

      if (!mounted) return;

      setState(() {
        _premiumActive = premiumActive;
        _premiumDaysLeft = premiumDays;
        _trialDaysLeft = trialDays;
        _trialActive = trialActive;

        _weeklyTotal = ReportService.sum(analytics.weekOrders);
        _monthlyTotal = ReportService.sum(analytics.monthOrders);
        _yearlyTotal = ReportService.sum(analytics.yearOrders);

        _weeklyCount = analytics.weekOrders.length;
        _monthlyCount = analytics.monthOrders.length;
        _yearlyCount = analytics.yearOrders.length;

        _weekRange =
        '${_formatShortDate(startOfWeek)} - ${_formatShortDate(endOfWeek)}';
        _monthRange =
        '${_formatShortDate(startOfMonth)} - ${_formatShortDate(endOfMonth)}';
        _yearRange = '${now.year}';

        _monthlyTrend = _buildMonthlyTrend(
          List<dynamic>.from(analytics.allOrders),
        );

        _topCustomer = analytics.topCustomer;
        _topProduct = analytics.topProduct;
      });
    } catch (_) {
      if (!mounted) return;

      final premiumActive = await LicenseManager.isPremiumActive();
      final premiumDays = await LicenseManager.getPremiumDaysLeft();
      final trialDays = await LicenseManager.getTrialDaysLeft();
      final trialActive = await LicenseManager.isTrialActive();

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 6));
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0);

      setState(() {
        _premiumActive = premiumActive;
        _premiumDaysLeft = premiumDays;
        _trialDaysLeft = trialDays;
        _trialActive = trialActive;

        _weeklyTotal = 0;
        _monthlyTotal = 0;
        _yearlyTotal = 0;

        _weeklyCount = 0;
        _monthlyCount = 0;
        _yearlyCount = 0;

        _weekRange =
        '${_formatShortDate(startOfWeek)} - ${_formatShortDate(endOfWeek)}';
        _monthRange =
        '${_formatShortDate(startOfMonth)} - ${_formatShortDate(endOfMonth)}';
        _yearRange = '${now.year}';

        _monthlyTrend = [];
        _topCustomer = null;
        _topProduct = null;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _buildOrganizerCard() {
    if (_premiumActive) {
      return GestureDetector(
        onTap: _openOrganizerOrSubscription,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFBBF7D0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  color: _green,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Organizer (Premium • $_premiumDaysLeft day${_premiumDaysLeft == 1 ? '' : 's'} left)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Color(0xFF14532D),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Premium is active on this device.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: _green,
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _openSubscriptionPage,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _trialDaysLeft > 0 ? Icons.schedule : Icons.lock_outline,
                color: _trialDaysLeft > 0 ? Colors.orange : Colors.grey,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _trialDaysLeft > 0
                        ? 'Organizer (Trial expires in $_trialDaysLeft day${_trialDaysLeft == 1 ? '' : 's'})'
                        : 'Organizer (Trial expired • Subscribe ₱149)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _trialDaysLeft > 0
                        ? 'Your trial is about to expire. Tap to subscribe.'
                        : 'Tap to subscribe or check activation status.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              _trialDaysLeft > 0 ? Icons.warning_amber_rounded : Icons.lock_rounded,
              size: 16,
              color: _trialDaysLeft > 0 ? Colors.orange : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _blue),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFF7FAFF),
            Color(0xFFFFFBF2),
            Color(0xFFF9FBFF),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: RefreshIndicator(
        color: _blue,
        onRefresh: _loadDashboard,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            12,
            _isCleanMode ? 24 : 12,
            12,
            24,
          ),
          children: [
            if (_premiumActive || _trialDaysLeft <= 3) ...[
              _buildOrganizerCard(),
              const SizedBox(height: 12),
            ],
            _SalesOverviewCard(
              weekRange: _weekRange,
              monthRange: _monthRange,
              yearRange: _yearRange,
              weekTotal: _weeklyTotal,
              monthTotal: _monthlyTotal,
              yearTotal: _yearlyTotal,
              weekCount: _weeklyCount,
              monthCount: _monthlyCount,
              yearCount: _yearlyCount,
              peso: _peso,
              compact: _isCleanMode,
            ),
            const SizedBox(height: 12),
            if (!_isCleanMode) ...[
              const _SectionTitle(
                icon: Icons.show_chart,
                title: 'Sales Trend (12 Months)',
                color: _green,
              ),
              const SizedBox(height: 6),
            ],
            _TrendCard(
              points: _monthlyTrend,
              peso: _peso,
              formatMonthYear: _formatMonthYear,
              compact: true,
            ),
            if (!_isCleanMode) ...[
              const SizedBox(height: 16),
              const _SectionTitle(
                icon: Icons.emoji_events_outlined,
                title: 'Top Customer',
                color: _gold,
              ),
              const SizedBox(height: 8),
              _TopCustomerCard(
                data: _topCustomer,
                peso: _peso,
                accent: _blue,
                accentSoft: _blueSoft,
                valueColor: _gold,
              ),
              const SizedBox(height: 16),
              const _SectionTitle(
                icon: Icons.inventory_2_outlined,
                title: 'Top Product',
                color: _gold,
              ),
              const SizedBox(height: 8),
              _TopProductCard(
                data: _topProduct,
                peso: _peso,
                accent: _blue,
                accentSoft: _goldSoft,
                valueColor: _gold,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isCleanMode
          ? null
          : AppBar(
        title: const Text(
          'Dashboard',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Clean Screen',
            onPressed: () {
              setState(() => _isCleanMode = true);
            },
            icon: const Icon(Icons.fullscreen),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh, color: _gold),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(),
          if (_isCleanMode)
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FloatingCircleButton(
                      icon: Icons.refresh,
                      onTap: _loadDashboard,
                    ),
                    const SizedBox(width: 10),
                    _FloatingCircleButton(
                      icon: Icons.close,
                      onTap: () {
                        setState(() => _isCleanMode = false);
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FloatingCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _FloatingCircleButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SalesOverviewCard extends StatelessWidget {
  final String weekRange;
  final String monthRange;
  final String yearRange;

  final double weekTotal;
  final double monthTotal;
  final double yearTotal;

  final int weekCount;
  final int monthCount;
  final int yearCount;

  final String Function(double) peso;
  final bool compact;

  const _SalesOverviewCard({
    required this.weekRange,
    required this.monthRange,
    required this.yearRange,
    required this.weekTotal,
    required this.monthTotal,
    required this.yearTotal,
    required this.weekCount,
    required this.monthCount,
    required this.yearCount,
    required this.peso,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD9E6FB)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _CompactSummaryTile(
                icon: Icons.calendar_today_outlined,
                title: 'Week',
                amount: peso(weekTotal),
                orders: weekCount,
                iconColor: const Color(0xFF2F6FD6),
                bgColor: const Color(0xFFDCEBFF),
                amountColor: const Color(0xFFD4A017),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CompactSummaryTile(
                icon: Icons.calendar_month_outlined,
                title: 'Month',
                amount: peso(monthTotal),
                orders: monthCount,
                iconColor: const Color(0xFF16A34A),
                bgColor: const Color(0xFFDCFCE7),
                amountColor: const Color(0xFF16A34A),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CompactSummaryTile(
                icon: Icons.bar_chart_outlined,
                title: 'Year',
                amount: peso(yearTotal),
                orders: yearCount,
                iconColor: const Color(0xFF2F6FD6),
                bgColor: const Color(0xFFDCEBFF),
                amountColor: const Color(0xFF2F6FD6),
              ),
            ),
          ],
        ),
      );
    }

    Widget row({
      required IconData icon,
      required String title,
      required String range,
      required double amount,
      required int orders,
      required Color iconColor,
      required Color bgColor,
      required Color amountColor,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    range,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'Total Sales',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  peso(amount),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: amountColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Orders: $orders',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD9E6FB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          row(
            icon: Icons.calendar_today_outlined,
            title: 'This Week',
            range: weekRange,
            amount: weekTotal,
            orders: weekCount,
            iconColor: const Color(0xFF2F6FD6),
            bgColor: const Color(0xFFDCEBFF),
            amountColor: const Color(0xFFD4A017),
          ),
          const Divider(height: 16),
          row(
            icon: Icons.calendar_month_outlined,
            title: 'This Month',
            range: monthRange,
            amount: monthTotal,
            orders: monthCount,
            iconColor: const Color(0xFF16A34A),
            bgColor: const Color(0xFFDCFCE7),
            amountColor: const Color(0xFF16A34A),
          ),
          const Divider(height: 16),
          row(
            icon: Icons.bar_chart_outlined,
            title: 'This Year',
            range: yearRange,
            amount: yearTotal,
            orders: yearCount,
            iconColor: const Color(0xFF2F6FD6),
            bgColor: const Color(0xFFDCEBFF),
            amountColor: const Color(0xFF2F6FD6),
          ),
        ],
      ),
    );
  }
}

class _CompactSummaryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String amount;
  final int orders;
  final Color iconColor;
  final Color bgColor;
  final Color amountColor;

  const _CompactSummaryTile({
    required this.icon,
    required this.title,
    required this.amount,
    required this.orders,
    required this.iconColor,
    required this.bgColor,
    required this.amountColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: amountColor,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$orders orders',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final List<MonthlySalesPoint> points;
  final String Function(double) peso;
  final String Function(DateTime) formatMonthYear;
  final bool compact;

  const _TrendCard({
    required this.points,
    required this.peso,
    required this.formatMonthYear,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final latest = points.isNotEmpty ? points.last : null;

    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 12,
        compact ? 8 : 12,
        compact ? 8 : 12,
        compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9E6FB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: points.isEmpty
          ? const Text(
        'No data',
        style: TextStyle(
          fontSize: 12,
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w600,
        ),
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                compact ? 'Sales Trend' : 'Sales Trend (12 Months)',
                style: TextStyle(
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: latest == null
                    ? const SizedBox.shrink()
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatMonthYear(latest.month),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: compact ? 10 : 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    Text(
                      peso(latest.total),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: compact ? 10 : 11,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 6 : 8),
          SizedBox(
            height: compact ? 44 : 56,
            child: CustomPaint(
              size: Size(double.infinity, compact ? 44 : 56),
              painter: _MonthlyTrendPainter(points: points),
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  formatMonthYear(points.first.month),
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: compact ? 9 : 10,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  formatMonthYear(points.last.month),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: compact ? 9 : 10,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopCustomerCard extends StatelessWidget {
  final TopCustomerStat? data;
  final String Function(double) peso;
  final Color accent;
  final Color accentSoft;
  final Color valueColor;

  const _TopCustomerCard({
    required this.data,
    required this.peso,
    required this.accent,
    required this.accentSoft,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD9E6FB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: data == null
          ? const Text(
        'No customer data yet.',
        style: TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w600,
        ),
      )
          : Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accentSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.person_outline,
              color: accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data!.customerName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Total Sales: ${peso(data!.totalSales)}',
                  style: TextStyle(
                    color: valueColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Orders: ${data!.orderCount}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopProductCard extends StatelessWidget {
  final TopProductStat? data;
  final String Function(double) peso;
  final Color accent;
  final Color accentSoft;
  final Color valueColor;

  const _TopProductCard({
    required this.data,
    required this.peso,
    required this.accent,
    required this.accentSoft,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8DFC3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: data == null
          ? const Text(
        'No product data yet.',
        style: TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w600,
        ),
      )
          : Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accentSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.medication_outlined,
              color: accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data!.brand,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Total Sales: ${peso(data!.totalSales)}',
                  style: TextStyle(
                    color: valueColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Paid Qty: ${data!.paidQty} • Free Qty: ${data!.freeQty}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Order Lines: ${data!.orderCount}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyTrendPainter extends CustomPainter {
  final List<MonthlySalesPoint> points;

  _MonthlyTrendPainter({
    required this.points,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final maxValue = points.map((e) => e.total).reduce((a, b) => a > b ? a : b);
    final minValue = points.map((e) => e.total).reduce((a, b) => a < b ? a : b);

    final range =
    (maxValue - minValue).abs() < 0.0001 ? 1.0 : (maxValue - minValue);

    final availableWidth = size.width <= 0 ? 1.0 : size.width;
    final dxStep =
    points.length <= 1 ? 0.0 : availableWidth / (points.length - 1);

    Offset pointOffset(int index) {
      final x = dxStep * index;
      final normalized = (points[index].total - minValue) / range;
      final y = size.height - (normalized * (size.height - 10)) - 5;
      return Offset(x, y);
    }

    if (points.length == 1) {
      final p = Offset(availableWidth / 2, size.height / 2);
      final dotPaint = Paint()
        ..color = const Color(0xFF16A34A)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, 3.0, dotPaint);
      return;
    }

    final path = Path();
    final fillPath = Path();

    final first = pointOffset(0);
    path.moveTo(first.dx, first.dy);
    fillPath.moveTo(first.dx, size.height);
    fillPath.lineTo(first.dx, first.dy);

    for (int i = 1; i < points.length; i++) {
      final p = pointOffset(i);
      path.lineTo(p.dx, p.dy);
      fillPath.lineTo(p.dx, p.dy);
    }

    final last = pointOffset(points.length - 1);
    fillPath.lineTo(last.dx, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0x2216A34A),
          Color(0x1116A34A),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = const Color(0xFF16A34A)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dotPaint = Paint()
      ..color = const Color(0xFF16A34A)
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    for (int i = 0; i < points.length; i++) {
      final p = pointOffset(i);
      canvas.drawCircle(p, 2.4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MonthlyTrendPainter oldDelegate) {
    if (oldDelegate.points.length != points.length) return true;

    for (int i = 0; i < points.length; i++) {
      if (oldDelegate.points[i].month != points[i].month ||
          oldDelegate.points[i].total != points[i].total) {
        return true;
      }
    }

    return false;
  }
}