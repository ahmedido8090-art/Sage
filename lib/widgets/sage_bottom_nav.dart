// widgets/sage_bottom_nav.dart
import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

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
        color: SageColors.chrome,
        border: Border(top: BorderSide(color: SageColors.line)),
      ),
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(_items.length, (i) {
            final selected = i == currentIndex;
            final item = _items[i];
            return Expanded(
              child: Semantics(
                button: true,
                selected: selected,
                label: item.label,
                child: InkWell(
                  onTap: () => onTap(i),
                  borderRadius: SageRadius.round(12),
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(minHeight: kSageMinTapTarget),
                    child: ExcludeSemantics(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item.icon,
                            size: 22,
                            color:
                                selected ? SageColors.moss : SageColors.inkSoft,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.label,
                            style: SageText.caption(
                              color: selected
                                  ? SageColors.moss
                                  : SageColors.inkSoft,
                            ).copyWith(
                              fontSize: 11,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 14,
                            height: 2,
                            decoration: BoxDecoration(
                              color: selected
                                  ? SageColors.amber
                                  : Colors.transparent,
                              borderRadius: SageRadius.round(2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
