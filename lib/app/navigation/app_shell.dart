import 'package:flutter/material.dart';

import '../../features/calendar/calendar_page.dart';
import '../../features/home/home_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/tools/tools_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  final GlobalKey<CalendarPageState> _calendarKey =
      GlobalKey<CalendarPageState>();

  final GlobalKey<ProfilePageState> _profileKey =
      GlobalKey<ProfilePageState>();

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();

    _pages = [
      HomePage(
        onAiUsageChanged: () async {
          await _profileKey.currentState?.refreshProfile();
        },
      ),

      CalendarPage(
        key: _calendarKey,
      ),

      const ToolsPage(),

      ProfilePage(
        key: _profileKey,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),

      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.navigationBarTheme.backgroundColor ??
              theme.colorScheme.surface,

          border: Border(
            top: BorderSide(
              color: theme.dividerColor,
              width: 0.8,
            ),
          ),
        ),

        child: SafeArea(
          top: false,
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedIndex: _selectedIndex,

            onDestinationSelected: (index) async {
              setState(() {
                _selectedIndex = index;
              });

              if (index == 1) {
                await _calendarKey.currentState
                    ?.refreshPlans();
              }

              if (index == 3) {
                await _profileKey.currentState
                    ?.refreshProfile();
              }
            },

            destinations: const [
              NavigationDestination(
                icon: Icon(
                  Icons.home_outlined,
                ),
                selectedIcon: Icon(
                  Icons.home_rounded,
                ),
                label: 'Home',
              ),

              NavigationDestination(
                icon: Icon(
                  Icons.calendar_today_outlined,
                ),
                selectedIcon: Icon(
                  Icons.calendar_month_rounded,
                ),
                label: 'Takvim',
              ),

              NavigationDestination(
                icon: Icon(
                  Icons.grid_view_outlined,
                ),
                selectedIcon: Icon(
                  Icons.grid_view_rounded,
                ),
                label: 'Araçlar',
              ),

              NavigationDestination(
                icon: Icon(
                  Icons.person_outline_rounded,
                ),
                selectedIcon: Icon(
                  Icons.person_rounded,
                ),
                label: 'Profil',
              ),
            ],
          ),
        ),
      ),
    );
  }
}