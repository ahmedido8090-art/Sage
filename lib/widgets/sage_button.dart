// widgets/sage_button.dart
//
// The shared button, with the states every action needs: ready, in progress
// (spinner, no double taps) and disabled (clearly muted, in both themes).
import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';

enum SageButtonStyle { primary, outlined }

class SageButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  /// Shows a spinner and ignores taps while work is happening.
  final bool loading;
  final IconData? icon;
  final bool expand;
  final SageButtonStyle style;

  const SageButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.expand = true,
    this.style = SageButtonStyle.primary,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final primary = style == SageButtonStyle.primary;
    final spinnerColor = primary ? SageColors.onAccent : SageColors.moss;

    final child = AnimatedSwitcher(
      duration: SageMotion.valueChange,
      child: loading
          ? SizedBox(
              key: const ValueKey('busy'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: spinnerColor),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: SageSpace.sm),
                ],
                Flexible(child: Text(label, textAlign: TextAlign.center)),
              ],
            ),
    );

    final button = primary
        ? ElevatedButton(
            onPressed: enabled ? onPressed : null,
            style: ElevatedButton.styleFrom(
              disabledBackgroundColor: SageColors.line,
              disabledForegroundColor: SageColors.inkSoft,
            ),
            child: child,
          )
        : OutlinedButton(
            onPressed: enabled ? onPressed : null,
            child: child,
          );

    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? '$label, in progress' : label,
      excludeSemantics: true,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}
