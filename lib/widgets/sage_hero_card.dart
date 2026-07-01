// widgets/sage_hero_card.dart
//
// Rebuilt on Reveal (large size, since this is a full-width hero surface,
// not a compact tile) and SageMotion tokens for its internal AnimatedSwitcher/
// AnimatedContainer/AnimatedOpacity timings — previously these were four
// different inline numbers (300/400/700/350ms) with no relationship to
// each other or to the rest of the app.
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import 'pulse_wave_painter.dart';
import 'animated_number.dart';
import 'reveal.dart';

class SageHeroCard extends StatelessWidget {
  final bool isConnected;
  final int batteryLevel;
  final int heartRate;
  final String subLabel;
  final VoidCallback onConnectPressed;

  const SageHeroCard({
    super.key,
    required this.isConnected,
    required this.batteryLevel,
    required this.heartRate,
    required this.onConnectPressed,
    this.subLabel = 'Resting',
  });

  @override
  Widget build(BuildContext context) {
    return Reveal(
      size: RevealSize.large,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        decoration: BoxDecoration(
          color: SageColors.heroBg,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: onConnectPressed,
                  child: AnimatedContainer(
                    duration: SageMotion.valueChange,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: SageMotion.valueChange,
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isConnected
                                ? SageColors.heroAccentOk
                                : SageColors.heroAccentWarn,
                          ),
                        ),
                        const SizedBox(width: 6),
                        AnimatedSwitcher(
                          duration: SageMotion.valueChange,
                          child: Text(
                            isConnected
                                ? 'Sage Band · Connected'
                                : 'Tap to connect band',
                            key: ValueKey(isConnected),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: SageColors.heroLabel,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedOpacity(
                  duration: SageMotion.valueChange,
                  opacity: isConnected ? 1.0 : 0.0,
                  child: Text(
                    '$batteryLevel%',
                    style: SageText.mono(
                      size: 11.5,
                      weight: FontWeight.w400,
                      color: SageColors.heroLabelMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                AnimatedNumber(
                  value: heartRate,
                  style: SageText.mono(
                    size: 52,
                    weight: FontWeight.w500,
                    color: SageColors.heroNumber,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'bpm',
                  style: TextStyle(
                    fontSize: 13,
                    color: SageColors.heroLabelMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            AnimatedSwitcher(
              duration: SageMotion.valueChange,
              child: Text(
                subLabel,
                key: ValueKey(subLabel),
                style: TextStyle(fontSize: 12.5, color: SageColors.heroSubLabel),
              ),
            ),
            const SizedBox(height: 10),
            PulseWave(
              height: 44,
              color: SageColors.heroLine,
              heartRate: heartRate,
              isLive: isConnected && heartRate > 0,
            ),
          ],
        ),
      ),
    );
  }
}
