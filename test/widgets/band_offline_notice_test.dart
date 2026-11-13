import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sage/band/band_monitor.dart';
import 'package:sage/models/health_data.dart';
import 'package:sage/theme/app_theme.dart';
import 'package:sage/widgets/band_offline_notice.dart';

class _Source implements BandSource {
  @override
  final ValueNotifier<bool> isConnected = ValueNotifier(false);
  @override
  Stream<HealthData> get dataStream => const Stream.empty();
}

/// A monitor whose snapshot the test sets directly: the widget only reads it.
BandMonitor _monitorWith(BandSnapshot snapshot) =>
    BandMonitor(source: _Source())..snapshot.value = snapshot;

Future<void> _pump(WidgetTester tester, Widget child, bool dark,
    {double textScale = 1.6}) async {
  await ThemeController.setDark(dark);
  tester.view.physicalSize = const Size(320, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(
        size: const Size(320, 900), textScaler: TextScaler.linear(textScale)),
    child: MaterialApp(
      theme: dark ? SageTheme.dark : SageTheme.light,
      home: Scaffold(
          backgroundColor: SageColors.linen,
          body: SingleChildScrollView(child: child)),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test('bandNoticeFor picks the right note', () {
    expect(bandNoticeFor(const BandSnapshot()), BandNoticeKind.neverConnected);
    expect(bandNoticeFor(const BandSnapshot(everSeen: true)),
        BandNoticeKind.disconnected);
    expect(bandNoticeFor(const BandSnapshot(connected: true, everSeen: true)),
        BandNoticeKind.quiet);
    expect(
        bandNoticeFor(
            const BandSnapshot(connected: true, everSeen: true, fresh: true)),
        isNull);
  });

  final cases = <String, (BandSnapshot, bool, String?)>{
    // name: (snapshot, shouldOfferConnect, expected text)
    'never connected': (const BandSnapshot(), true, 'Live tracking is off'),
    'disconnected': (
      BandSnapshot(
          everSeen: true,
          heartRate: 70,
          lastReadingAt: DateTime.now().subtract(const Duration(minutes: 5))),
      true,
      'connected'
    ),
    'connected but quiet': (
      const BandSnapshot(connected: true, everSeen: true),
      false,
      'Waiting on your band'
    ),
  };

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    for (final compact in [false, true]) {
      final variant = compact ? 'compact' : 'full';

      for (final entry in cases.entries) {
        testWidgets('$mode $variant: ${entry.key}', (tester) async {
          final (snapshot, offersConnect, text) = entry.value;
          await _pump(
              tester,
              BandOfflineNotice(
                  featureName: 'Walking',
                  compact: compact,
                  monitor: _monitorWith(snapshot)),
              dark);
          expect(find.textContaining(text!), findsWidgets);
          expect(find.text('Connect band'),
              offersConnect ? findsOneWidget : findsNothing);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('$mode $variant: shows when it last synced', (tester) async {
        await _pump(
            tester,
            BandOfflineNotice(
                featureName: 'Walking',
                compact: compact,
                monitor: _monitorWith(BandSnapshot(
                    everSeen: true,
                    lastReadingAt:
                        DateTime.now().subtract(const Duration(minutes: 7))))),
            dark);
        expect(find.textContaining('Last synced 7 min ago'), findsOneWidget);
      });

      testWidgets('$mode $variant: renders nothing while readings are live',
          (tester) async {
        await _pump(
            tester,
            BandOfflineNotice(
                featureName: 'Walking',
                compact: compact,
                monitor: _monitorWith(const BandSnapshot(
                    connected: true, everSeen: true, fresh: true))),
            dark);
        expect(find.text('Connect band'), findsNothing);
        expect(find.textContaining('Walking'), findsNothing);
      });
    }
  }

  testWidgets('appears and disappears as the band comes and goes',
      (tester) async {
    final monitor = _monitorWith(const BandSnapshot());
    await _pump(
        tester,
        BandOfflineNotice(
            featureName: 'Walking', compact: true, monitor: monitor),
        false);
    expect(find.text('Connect band'), findsOneWidget);

    monitor.snapshot.value =
        const BandSnapshot(connected: true, everSeen: true, fresh: true);
    await tester.pumpAndSettle();
    expect(find.text('Connect band'), findsNothing);

    monitor.snapshot.value = const BandSnapshot(everSeen: true);
    await tester.pumpAndSettle();
    expect(find.text('Connect band'), findsOneWidget);
  });
}
