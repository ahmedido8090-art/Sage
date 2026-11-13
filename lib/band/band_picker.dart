// band/band_picker.dart
//
// The connect-your-band flow, shared by Home and by every screen that offers
// "Connect band". It only reads the Bluetooth service (scan results, connect
// and disconnect calls); the service itself is untouched.
import 'dart:async';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import '../services/bluetooth_service.dart';
import '../services/system_settings.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/friendly_error.dart';
import '../widgets/pressable.dart';
import '../widgets/sage_feedback.dart';
import '../widgets/sage_illustration.dart';
import '../widgets/sage_states.dart';
import '../widgets/state_copy.dart';

/// Opens the band picker as a bottom sheet.
Future<void> showBandPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: SageColors.cardRaised,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    builder: (ctx) => _DevicePickerSheet(btService: BluetoothService.instance),
  );
}

// ── Device picker bottom sheet ─────────────────────────────────────────────
//
// Reads the band service from the outside only (scan results and errors); the
// service itself is untouched. Covers scanning, found, nothing found and
// error, each with a next step.
class _DevicePickerSheet extends StatefulWidget {
  final BluetoothService btService;
  const _DevicePickerSheet({required this.btService});

  @override
  State<_DevicePickerSheet> createState() => _DevicePickerSheetState();
}

class _DevicePickerSheetState extends State<_DevicePickerSheet> {
  /// How long to show "looking" before concluding nothing is nearby.
  static const _scanWindow = Duration(seconds: 6);

  Timer? _scanTimer;
  bool _scanning = true;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  void _scan() {
    widget.btService.startScan();
    _scanTimer?.cancel();
    setState(() => _scanning = true);
    _scanTimer = Timer(_scanWindow, () {
      if (mounted) setState(() => _scanning = false);
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    widget.btService.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 440,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              SageSpace.xl, SageSpace.xl, SageSpace.xl, SageSpace.lg),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text('Select your band', style: SageText.title())),
                  if (!_scanning)
                    TextButton.icon(
                      onPressed: _scan,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Scan again'),
                    ),
                ],
              ),
              if (Platform.isAndroid) ...[
                const SizedBox(height: SageSpace.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'If you don\'t see your band, pair it in Android Bluetooth '
                    'settings first.',
                    style: SageText.caption(),
                  ),
                ),
              ],
              const SizedBox(height: SageSpace.md),
              Expanded(
                child: StreamBuilder<List<SageDevice>>(
                  stream: widget.btService.scanResults,
                  initialData: const [],
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return ErrorState(
                        error: snapshot.error,
                        compact: true,
                        onRetry: _scan,
                      );
                    }
                    final devices = snapshot.data ?? [];
                    if (devices.isEmpty) {
                      return _scanning
                          ? const _ScanningState()
                          : _NothingFound(onRescan: _scan);
                    }
                    return ListView.separated(
                      itemCount: devices.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: SageSpace.sm),
                      itemBuilder: (ctx, i) => _DeviceTile(
                        device: devices[i],
                        onTap: () {
                          final messenger = ScaffoldMessenger.of(context);
                          Navigator.pop(context);
                          _connectTo(messenger, devices[i]);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Runs after the sheet has closed, so feedback goes through a messenger
  // captured beforehand instead of this (by then disposed) state's context.
  Future<void> _connectTo(
      ScaffoldMessengerState messenger, SageDevice device) async {
    SageFeedback.infoOn(messenger, 'Connecting to ${device.name}...');
    try {
      await widget.btService.connect(device);
      SageFeedback.successOn(messenger, 'Connected. Your band is live.');
    } catch (e, st) {
      SageFeedback.problemOn(
        messenger,
        humanizeError(e, stackTrace: st).message,
        actionLabel: 'Try again',
        onAction: () => _connectTo(messenger, device),
      );
    }
  }
}

class _ScanningState extends StatelessWidget {
  const _ScanningState();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Looking for your band',
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SageIllustration(
              art: SageArt.band,
              size: 112,
              motion: SageArtMotion.breathe,
            ),
            const SizedBox(height: SageSpace.lg),
            Text('Looking for your band…', style: SageText.title()),
            const SizedBox(height: SageSpace.xs),
            Text('Keep it close and switched on.', style: SageText.caption()),
          ],
        ),
      ),
    );
  }
}

class _NothingFound extends StatelessWidget {
  final VoidCallback onRescan;
  const _NothingFound({required this.onRescan});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: EmptyState.topic(
        StateTopic.bands,
        art: SageArt.band,
        compact: true,
        actionLabel: 'Scan again',
        onAction: onRescan,
        secondaryLabel: 'Bluetooth settings',
        onSecondary: SystemSettings.openBluetooth,
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final SageDevice device;
  final VoidCallback onTap;
  const _DeviceTile({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = device.name.isEmpty ? 'Unknown device' : device.name;
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Connect to $name',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: kSageMinTapTarget + 12),
          padding: const EdgeInsets.symmetric(
              horizontal: SageSpace.lg, vertical: SageSpace.md),
          decoration: BoxDecoration(
            color: SageColors.card,
            borderRadius: SageRadius.tile,
            border: Border.all(color: SageColors.line),
          ),
          child: Row(
            children: [
              Icon(device.isBle ? Icons.bluetooth : Icons.bluetooth_searching,
                  color: SageColors.moss),
              const SizedBox(width: SageSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: SageText.label()),
                    Text(device.id, style: SageText.caption()),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: SageColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}
