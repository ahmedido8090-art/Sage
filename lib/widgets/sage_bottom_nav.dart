// widgets/sage_bottom_nav.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class _SageNavItem {
  final IconData icon;
  final String label;
  const _SageNavItem({required this.icon, required this.label});
}

/// Bottom navigation bar with a thin amber underline on the active tab,
/// echoing the pulse-wave signature instead of a filled pill indicator.
class SageBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const SageBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = [
    _SageNavItem(icon: Icons.home_outlined, label: 'Home'),
    _SageNavItem(icon: Icons.spa_outlined, label: 'Wellness'),
    _SageNavItem(icon: Icons.bar_chart_outlined, label: 'Insights'),
    _SageNavItem(icon: Icons.person_outline, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SageColors.linen,
        border: Border(top: BorderSide(color: SageColors.line)),
      ),
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(_items.length, (i) {
            final selected = i == currentIndex;
            final item = _items[i];
            return InkWell(
              onTap: () => onTap(i),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.icon,
                      size: 22,
                      color: selected ? SageColors.moss : SageColors.inkSoft,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 14,
                      height: 2,
                      decoration: BoxDecoration(
                        color: selected ? SageColors.amber : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}