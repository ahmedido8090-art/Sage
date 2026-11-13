// widgets/sage_feedback.dart
//
// Success, info and gentle-error feedback as a floating pill, the same in
// every screen and both themes. Success gets a small bouncing check.
import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'state_copy.dart';

class SageFeedback {
  SageFeedback._();

  /// A success pill. Pass [message], or leave it out for a varied "All set".
  static void success(BuildContext context, [String? message]) =>
      successOn(ScaffoldMessenger.of(context), message);

  static void info(BuildContext context, String message) =>
      infoOn(ScaffoldMessenger.of(context), message);

  /// A calm heads-up: says what happened and never blames.
  static void problem(BuildContext context, String message,
          {String? actionLabel, VoidCallback? onAction}) =>
      problemOn(ScaffoldMessenger.of(context), message,
          actionLabel: actionLabel, onAction: onAction);

  // The `...On` variants take a messenger captured earlier, for feedback that
  // arrives after the widget that triggered it (a bottom sheet) has closed.

  static void successOn(ScaffoldMessengerState messenger, [String? message]) =>
      _show(messenger, message ?? StateCopy.success().message,
          Icons.check_rounded, SageColors.moss,
          bounce: true);

  static void infoOn(ScaffoldMessengerState messenger, String message) =>
      _show(messenger, message, Icons.info_outline_rounded, SageColors.moss);

  static void problemOn(ScaffoldMessengerState messenger, String message,
          {String? actionLabel, VoidCallback? onAction}) =>
      _show(messenger, message, Icons.error_outline_rounded, SageColors.clay,
          actionLabel: actionLabel, onAction: onAction);

  static void _show(
    ScaffoldMessengerState messenger,
    String message,
    IconData icon,
    Color tone, {
    bool bounce = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: Duration(seconds: actionLabel == null ? 3 : 6),
      action: actionLabel == null || onAction == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction),
      content: Row(
        children: [
          _Badge(icon: icon, tone: tone, bounce: bounce),
          const SizedBox(width: SageSpace.md),
          Expanded(child: Text(message)),
        ],
      ),
    ));
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final Color tone;
  final bool bounce;
  const _Badge({required this.icon, required this.tone, required this.bounce});

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
      child: Icon(icon, size: 18, color: SageColors.onFill(tone)),
    );
    if (!bounce || MediaQuery.disableAnimationsOf(context)) return badge;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1),
      duration: SageMotion.bounceDuration,
      curve: SageMotion.bounceCurve,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
      child: badge,
    );
  }
}
