import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Adaptive app shell: bottom navigation bar on phones, navigation rail
/// on tablets/desktop/web (Material 3 canonical layouts).
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    (icon: Icons.chat_bubble_outline, selected: Icons.chat_bubble, label: 'Chat'),
    (icon: Icons.auto_awesome_outlined, selected: Icons.auto_awesome, label: 'Werkzeuge'),
    (icon: Icons.check_circle_outline, selected: Icons.check_circle, label: 'Aufgaben'),
    (icon: Icons.sticky_note_2_outlined, selected: Icons.sticky_note_2, label: 'Notizen'),
    (icon: Icons.calendar_month_outlined, selected: Icons.calendar_month, label: 'Kalender'),
    (icon: Icons.settings_outlined, selected: Icons.settings, label: 'Mehr'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;

    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _goBranch,
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selected),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ]),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _goBranch,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: d.label),
        ],
      ),
    );
  }

  void _goBranch(int index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );
}
