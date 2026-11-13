// widgets/sage_states.dart
//
// The shared in-between states: nothing here yet, something went wrong,
// permission needed, and a slim inline banner. One look and one voice, in
// both themes, and every one of them offers a next step.
import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/friendly_error.dart';
import 'sage_button.dart';
import 'sage_illustration.dart';
import 'state_copy.dart';

/// Nothing to show yet. Playful, with an invitation to do something.
class EmptyState extends StatelessWidget {
  final SageArt art;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final Color? accent;

  /// Tighter spacing and a smaller illustration, for use inside a card.
  final bool compact;

  const EmptyState({
    super.key,
    required this.art,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.accent,
    this.compact = false,
  });

  /// Builds an empty state from the shared copy bank, rotating the wording.
  factory EmptyState.topic(
    StateTopic topic, {
    Key? key,
    required SageArt art,
    String? actionLabel,
    VoidCallback? onAction,
    String? secondaryLabel,
    VoidCallback? onSecondary,
    Color? accent,
    bool compact = false,
    int? variant,
  }) {
    final text = StateCopy.empty(topic, variant: variant);
    return EmptyState(
      key: key,
      art: art,
      title: text.title,
      message: text.message,
      actionLabel: actionLabel,
      onAction: onAction,
      secondaryLabel: secondaryLabel,
      onSecondary: onSecondary,
      accent: accent,
      compact: compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _StateLayout(
      art: art,
      motion: SageArtMotion.sway,
      accent: accent,
      title: title,
      message: message,
      compact: compact,
      actionLabel: actionLabel,
      onAction: onAction,
      secondaryLabel: secondaryLabel,
      onSecondary: onSecondary,
      liveRegion: false,
    );
  }
}

/// Something went wrong. Calm and plain: what happened in human words, and a
/// way to try again. Never shows raw exception text.
class ErrorState extends StatelessWidget {
  final Object? error;
  final String? title;
  final String? message;
  final VoidCallback onRetry;
  final String retryLabel;
  final bool retrying;
  final bool compact;

  const ErrorState({
    super.key,
    required this.onRetry,
    this.error,
    this.title,
    this.message,
    this.retryLabel = 'Try again',
    this.retrying = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final friendly = humanizeError(error);
    return _StateLayout(
      art: friendly.kind == ErrorKind.band ? SageArt.band : SageArt.calm,
      motion: SageArtMotion.still,
      accent: SageColors.amber,
      title: title ?? friendly.title,
      message: message ?? friendly.message,
      compact: compact,
      actionLabel: retryLabel,
      onAction: retrying ? null : onRetry,
      actionLoading: retrying,
      liveRegion: true,
    );
  }
}

enum PermissionKind { notifications, bluetooth, location }

/// A permission is needed. Explains why, offers the prompt, and once the
/// system has stopped asking, points the way to Settings.
class PermissionState extends StatelessWidget {
  final PermissionKind kind;

  /// True once the system will no longer show its own prompt.
  final bool blocked;
  final VoidCallback onAllow;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onNotNow;
  final bool compact;

  const PermissionState({
    super.key,
    required this.kind,
    required this.onAllow,
    this.blocked = false,
    this.onOpenSettings,
    this.onNotNow,
    this.compact = false,
  });

  static const _copy = {
    PermissionKind.notifications: (
      SageArt.bell,
      'Let Sage say hello now and then',
      'Notifications let Sage nudge you about water, rest and check-ins. '
          'You choose what and when.',
      'Notifications are switched off for Sage. Open Settings, tap '
          'Notifications, and turn them on.',
    ),
    PermissionKind.bluetooth: (
      SageArt.band,
      'Sage needs Bluetooth to find your band',
      'It is only used to talk to your Sage Band, nothing else.',
      'Bluetooth access is off for Sage. Open Settings and allow Nearby '
          'devices (or Bluetooth) for Sage.',
    ),
    PermissionKind.location: (
      SageArt.band,
      'Android asks for location to scan',
      'Your phone requires it to look for nearby Bluetooth devices. Sage '
          'never tracks where you are.',
      'Location access is off for Sage. Open Settings and allow it while '
          'using the app.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final (art, title, why, fix) = _copy[kind]!;
    return _StateLayout(
      art: art,
      motion: SageArtMotion.still,
      accent: SageColors.moss,
      title: blocked ? 'Almost there' : title,
      message: blocked ? fix : why,
      compact: compact,
      actionLabel: blocked ? 'Open Settings' : 'Allow',
      onAction: blocked ? (onOpenSettings ?? onAllow) : onAllow,
      secondaryLabel: onNotNow == null ? null : 'Not now',
      onSecondary: onNotNow,
      liveRegion: false,
    );
  }
}

enum BannerKind { info, success, warning, error }

/// A slim inline note for partial, stale or heads-up information, optionally
/// with one action.
class StatusBanner extends StatelessWidget {
  final BannerKind kind;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const StatusBanner({
    super.key,
    required this.message,
    this.kind = BannerKind.info,
    this.actionLabel,
    this.onAction,
  });

  (IconData, Color) get _style => switch (kind) {
        BannerKind.info => (Icons.info_outline_rounded, SageColors.moss),
        BannerKind.success => (
            Icons.check_circle_outline_rounded,
            SageColors.moss
          ),
        BannerKind.warning => (Icons.wb_twilight_rounded, SageColors.amber),
        BannerKind.error => (Icons.error_outline_rounded, SageColors.clay),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = _style;
    final accent = SageColors.legible(tone);
    return Semantics(
      liveRegion: kind == BannerKind.error || kind == BannerKind.warning,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: SageSpace.lg, vertical: SageSpace.md),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: SageColors.isDark ? 0.16 : 0.12),
          borderRadius: SageRadius.tile,
          border: Border.all(color: tone.withValues(alpha: 0.4)),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final hasAction = actionLabel != null && onAction != null;
            // Beside the message when there is room; underneath when the
            // screen is narrow or the text is large, so nothing overflows.
            final stacked = hasAction &&
                (box.maxWidth < 340 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.25);
            final message = Text(this.message,
                style: SageText.caption(color: SageColors.ink));
            final action = hasAction
                ? TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      minimumSize:
                          const Size(kSageMinTapTarget, kSageMinTapTarget),
                    ),
                    child: Text(actionLabel!),
                  )
                : null;
            return Row(
              crossAxisAlignment: stacked
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: accent),
                const SizedBox(width: SageSpace.md),
                Expanded(
                  child: stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            message,
                            Align(
                                alignment: Alignment.centerRight,
                                child: action),
                          ],
                        )
                      : message,
                ),
                if (!stacked && action != null) action,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StateLayout extends StatelessWidget {
  final SageArt art;
  final SageArtMotion motion;
  final Color? accent;
  final String title;
  final String message;
  final bool compact;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool actionLoading;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool liveRegion;

  const _StateLayout({
    required this.art,
    required this.motion,
    required this.accent,
    required this.title,
    required this.message,
    required this.compact,
    required this.liveRegion,
    this.actionLabel,
    this.onAction,
    this.actionLoading = false,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final pad = compact ? SageSpace.lg : SageSpace.xxl;
    return Semantics(
      liveRegion: liveRegion,
      container: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding:
                EdgeInsets.symmetric(horizontal: SageSpace.xl, vertical: pad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SageIllustration(
                  art: art,
                  size: compact ? 96 : 132,
                  accent: accent,
                  motion: motion,
                ),
                SizedBox(height: compact ? SageSpace.md : SageSpace.xl),
                Text(title,
                    textAlign: TextAlign.center, style: SageText.title()),
                const SizedBox(height: SageSpace.sm),
                Text(message,
                    textAlign: TextAlign.center,
                    style: SageText.body(color: SageColors.inkSoft)),
                if (actionLabel != null) ...[
                  SizedBox(height: compact ? SageSpace.lg : SageSpace.xl),
                  SageButton(
                    label: actionLabel!,
                    onPressed: onAction,
                    loading: actionLoading,
                    expand: false,
                  ),
                ],
                if (secondaryLabel != null && onSecondary != null) ...[
                  const SizedBox(height: SageSpace.xs),
                  TextButton(
                    onPressed: onSecondary,
                    style: TextButton.styleFrom(
                      minimumSize:
                          const Size(kSageMinTapTarget, kSageMinTapTarget),
                    ),
                    child: Text(secondaryLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
