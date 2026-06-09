// lib/ui/shell/main_shell.dart
// Bottom navigation shell wrapping the 5 main sections

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _tabs = [
    (icon: Icons.point_of_sale_rounded,  label: 'POS',        path: '/pos'),
    (icon: Icons.inventory_2_outlined,   label: 'Inventory',  path: '/inventory'),
    (icon: Icons.people_outline,         label: 'Customers',  path: '/customers'),
    (icon: Icons.bar_chart_rounded,      label: 'Reports',    path: '/reports'),
    (icon: Icons.settings_outlined,      label: 'Settings',   path: '/settings'),
  ];

  int _indexFromLocation(String loc) {
    for (var i = 0; i < _tabs.length; i++) {
      if (loc.startsWith(_tabs[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _indexFromLocation(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
        ),
        child: NavigationBar(
          backgroundColor: AppTheme.surface,
          elevation: 0,
          selectedIndex: selectedIndex,
          onDestinationSelected: (i) => context.go(_tabs[i].path),
          destinations: _tabs.map((t) => NavigationDestination(
            icon: Icon(t.icon),
            label: t.label,
          )).toList(),
        ),
      ),
    );
  }
}
