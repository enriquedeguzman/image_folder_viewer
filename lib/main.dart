import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'features/calculator/calculator_page.dart';
import 'features/calendar_notes/calendar_notes_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/detailing/detailing_page.dart';
import 'features/organizer/organizer_page.dart';
import 'firebase_options.dart';
import 'services/license_manager.dart';
import 'services/pricelist_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await LicenseManager.initialize();
  await PricelistManager.ensureBundledPricelistImported();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const Color _seedColor = Color(0xFF5B8DEF);
  static const Color _navBlue = Color(0xFF2F6FD6);
  static const Color _navGold = Color(0xFFD4A017);
  static const Color _navSoft = Color(0xFFFFF4CC);

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF4F7FB),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF4F7FB),
        foregroundColor: Color(0xFF1F2937),
        elevation: 0,
        centerTitle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: _navSoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? _navGold : const Color(0xFF5B6472),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? _navBlue : const Color(0xFF5B6472),
          );
        }),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My Organizer App',
      theme: baseTheme,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const List<Widget> _pages = [
    DashboardPage(),
    OrganizerPage(),
    DetailingPage(),
    CalendarNotesPage(),
    CalculatorPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() {
            _index = value;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Organizer',
          ),
          NavigationDestination(
            icon: Icon(Icons.medical_information_outlined),
            selectedIcon: Icon(Icons.medical_information),
            label: 'Detailing',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.calculate_outlined),
            selectedIcon: Icon(Icons.calculate),
            label: 'Calc',
          ),
        ],
      ),
    );
  }
}