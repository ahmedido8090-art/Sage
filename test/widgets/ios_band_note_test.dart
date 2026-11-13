import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sage/theme/app_theme.dart';
import 'package:sage/widgets/ios_band_note.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('is a hint, not a verdict, and says what still works', () {
    expect(IosBandNote.message, startsWith('Not seeing your band?'));
    expect(IosBandNote.message, contains('Bluetooth LE'));
    expect(IosBandNote.message, contains('works either way'));
    expect(IosBandNote.message, isNot(contains('HC-05')));
  });

  testWidgets('shows nothing off iOS unless forced', (tester) async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: IosBandNote())));
    expect(find.textContaining('Not seeing your band?'),
        findsNothing); // tests run on Linux
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets(
          'renders without overflow (${dark ? 'dark' : 'light'}, '
          '${scale}x, 320px)', (tester) async {
        SharedPreferences.setMockInitialValues({});
        GoogleFonts.config.allowRuntimeFetching = false;
        await ThemeController.setDark(dark);
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(
              size: const Size(320, 800), textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            theme: dark ? SageTheme.dark : SageTheme.light,
            home: const Scaffold(
              body: SingleChildScrollView(child: IosBandNote(forceShow: true)),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Not seeing your band?'), findsOneWidget);
      });
    }
  }
}
