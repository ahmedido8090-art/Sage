// widgets/band_offline_notice.dart
//
// The friendly note that stands in for live metrics when the band is not
// delivering them. It says plainly that the feature still works, that only
// live tracking is paused, and offers one calm way to connect. It listens to
// the band itself and renders nothing while readings are live, so a screen
// can place it unconditionally.
import 'package:material_ui/material_ui.dart';
import '../band/band_monitor.dart';
import '../band/band_picker.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'sage_button.dart';
import 'sage_card.dart';
import 'sage_illustration.dart';
import 'sage_states.dart';

enum BandNoticeKind { neverConnected, disconnected, quiet }

/// Which note fits the band's current state, or null when readings are live.
BandNoticeKind? bandNoticeFor(BandSnapshot s) {
  if (s.isLive) return null;
  if (s.connected) return BandNoticeKind.quiet;
  return s.everSeen
      ? BandNoticeKind.disconnected
      : BandNoticeKind.neverConnected;
}

class BandOfflineNotice extends StatelessWidget {
  /// What the screen is about, used in the copy: "Meditation works without...".
  final String featureName;

  /// A single slim row instead of a card.
  final bool compact;

  /// Replaces the sentence about what still works, for screens where it is
  /// more specific.
  final String? whatWorks;

  /// Where the monitor is read from (the app-wide one unless a test says so).
  final BandMonitor? monitor;

  const BandOfflineNotice({
    super.key,
    required this.featureName,
    this.compact = false,
    this.whatWorks,
    this.monitor,
  });

  @override
  Widget build(BuildContext context) {
    final source = monitor ?? BandMonitor.instance;
    return ValueListenableBuilder<BandSnapshot>(
      valueListenable: source.snapshot,
      builder: (context, snap, _) {
        final kind = bandNoticeFor(snap);
        return AnimatedSwitcher(
          duration: SageMotion.valueChange,
          switchInCurve: SageMotion.revealCurve,
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: kind == null
              ? const SizedBox.shrink(key: ValueKey('live'))
              : KeyedSubtree(
                  key: ValueKey(kind),
                  child: compact
                      ? _compact(context, kind, snap)
                      : _full(context, kind, snap),
                ),
        );
      },
    );
  }

  String _title(BandNoticeKind kind) => switch (kind) {
        BandNoticeKind.neverConnected => 'Live tracking is off',
        BandNoticeKind.disconnected => 'Your band isn\'t connected',
        BandNoticeKind.quiet => 'Waiting on your band',
      };

  String _message(BandNoticeKind kind, BandSnapshot snap) {
    final works = whatWorks ?? '$featureName works just fine without it.';
    return switch (kind) {
      BandNoticeKind.neverConnected =>
        '$works Connect your band whenever you like for live heart rate and steps.',
      BandNoticeKind.disconnected =>
        '$works Live heart rate and steps will pick up again when you reconnect.',
      BandNoticeKind.quiet =>
        'It\'s connected but quiet right now. Keep it close and snug on your wrist.',
    };
  }

  Widget _full(BuildContext context, BandNoticeKind kind, BandSnapshot snap) {
    final canConnect = kind != BandNoticeKind.quiet;
    return SageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SageIllustration(art: SageArt.band, size: 64),
              const SizedBox(width: SageSpace.lg),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_title(kind), style: SageText.title()),
                      const SizedBox(height: SageSpace.xs),
                      Text(_message(kind, snap),
                          style: SageText.body(color: SageColors.inkSoft)),
                      if (kind == BandNoticeKind.disconnected &&
                          snap.lastReadingAt != null) ...[
                        const SizedBox(height: SageSpace.sm),
                        Text(describeSynced(snap.lastReadingAt),
                            style: SageText.caption()),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (canConnect) ...[
            const SizedBox(height: SageSpace.lg),
            SageButton(
              label: 'Connect band',
              icon: Icons.bluetooth_rounded,
              style: SageButtonStyle.outlined,
              onPressed: () => showBandPicker(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _compact(
      BuildContext context, BandNoticeKind kind, BandSnapshot snap) {
    final canConnect = kind != BandNoticeKind.quiet;
    final synced =
        kind == BandNoticeKind.disconnected && snap.lastReadingAt != null
            ? ' ${describeSynced(snap.lastReadingAt)}.'
            : '';
    return StatusBanner(
      kind: kind == BandNoticeKind.neverConnected
          ? BannerKind.info
          : BannerKind.warning,
      message: switch (kind) {
        BandNoticeKind.neverConnected =>
          'Live tracking is off. $featureName works without your band.',
        BandNoticeKind.disconnected =>
          'Band disconnected. $featureName still works.$synced',
        BandNoticeKind.quiet => 'Waiting on your band. Keep it close.',
      },
      actionLabel: canConnect ? 'Connect band' : null,
      onAction: canConnect ? () => showBandPicker(context) : null,
    );
  }
}
