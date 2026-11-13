// widgets/ios_band_note.dart
//
// On iPhone only: a gentle hint for when a scan finds nothing. iOS can only
// talk to Bluetooth Low Energy devices, so a module that is classic-only will
// not appear. Shown just in the empty-scan state, never on Android, and never
// as a warning to someone whose band is already connecting.
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import '../theme/tokens.dart';
import 'sage_states.dart';

class IosBandNote extends StatelessWidget {
  /// Show it on any platform. For tests.
  final bool forceShow;

  const IosBandNote({super.key, this.forceShow = false});

  static const String message =
      'Not seeing your band? iPhones only find bands that use Bluetooth LE, '
      'so make sure your band\'s Bluetooth module supports it. Everything '
      'else in Sage works either way.';

  @override
  Widget build(BuildContext context) {
    if (!forceShow && !Platform.isIOS) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(top: SageSpace.lg),
      child: StatusBanner(kind: BannerKind.info, message: message),
    );
  }
}
