// widgets/band_intro_card.dart
//
// A one-time walkthrough on Home for people who have never connected a band.
// Three real steps, one action, and an honest note that Sage works without it.
import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'sage_button.dart';
import 'sage_card.dart';
import 'sage_illustration.dart';

class BandIntroCard extends StatelessWidget {
  final VoidCallback onConnect;
  final VoidCallback onDismiss;

  const BandIntroCard({
    super.key,
    required this.onConnect,
    required this.onDismiss,
  });

  static const _steps = [
    (Icons.power_settings_new_rounded, 'Switch it on and wear it snug.'),
    (Icons.bluetooth_rounded, 'Turn on Bluetooth and keep it close.'),
    (Icons.touch_app_rounded, 'Tap Connect and pick your band.'),
  ];

  @override
  Widget build(BuildContext context) {
    return SageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SageIllustration(
                art: SageArt.band,
                size: 72,
                motion: SageArtMotion.breathe,
              ),
              const SizedBox(width: SageSpace.lg),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Meet your Sage Band', style: SageText.title()),
                ),
              ),
            ],
          ),
          const SizedBox(height: SageSpace.md),
          Text(
            'It adds live heart rate and step counts. Everything else in Sage '
            'works without it, so there\'s no rush.',
            style: SageText.body(color: SageColors.inkSoft),
          ),
          const SizedBox(height: SageSpace.lg),
          for (var i = 0; i < _steps.length; i++) ...[
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: SageColors.moss.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_steps[i].$1, size: 18, color: SageColors.moss),
                ),
                const SizedBox(width: SageSpace.md),
                Expanded(
                  child:
                      Text('${i + 1}. ${_steps[i].$2}', style: SageText.body()),
                ),
              ],
            ),
            if (i != _steps.length - 1) const SizedBox(height: SageSpace.md),
          ],
          const SizedBox(height: SageSpace.xl),
          SageButton(
            label: 'Connect band',
            icon: Icons.bluetooth_rounded,
            onPressed: onConnect,
          ),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(
                minimumSize: const Size(kSageMinTapTarget, kSageMinTapTarget),
              ),
              child: const Text('Maybe later'),
            ),
          ),
        ],
      ),
    );
  }
}
