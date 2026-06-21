import 'package:flutter/material.dart';
import '../theme/bella_theme.dart';

class DeviceStatusCard extends StatelessWidget {
  final bool isConnected;
  final int batteryLevel;
  final double heartRate;
  final VoidCallback onConnectPressed;

  const DeviceStatusCard({
    super.key,
    required this.isConnected,
    required this.batteryLevel,
    required this.heartRate,
    required this.onConnectPressed,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isConnected ? BellaColors.success : BellaColors.warning;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: BellaColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: BellaColors.divider),
        boxShadow: [
          BoxShadow(
            color: BellaColors.cardGlow.withOpacity(0.16),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  BellaColors.primary.withOpacity(0.18),
                  BellaColors.accent.withOpacity(0.10),
                ],
              ),
              border: Border.all(color: BellaColors.primary.withOpacity(0.25)),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    heartRate.round().toString(),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: BellaColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'BPM',
                    style:
                        TextStyle(color: BellaColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Bella Band',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: BellaColors.textPrimary,
                      ),
                    ),
                    _buildStatusChip(statusColor),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.battery_full,
                        size: 16, color: BellaColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'Battery: $batteryLevel%',
                      style: const TextStyle(
                          color: BellaColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: onConnectPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isConnected
                        ? BellaColors.surfaceSoft
                        : BellaColors.primaryDeep,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(isConnected ? 'Disconnect' : 'Connect Band'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(Color statusColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            size: 14,
            color: statusColor,
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? 'Connected' : 'Disconnected',
            style: TextStyle(
                color: statusColor, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
