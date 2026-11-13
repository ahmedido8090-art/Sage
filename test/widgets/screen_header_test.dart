import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sage/theme/app_theme.dart';
import 'package:sage/widgets/sage_screen_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets(
          'header never overflows (${dark ? 'dark' : 'light'}, '
          '${scale}x text, 320px)', (tester) async {
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
              body: SafeArea(
                child: SageScreenHeader(
                  title: 'A rather long screen title for a narrow phone',
                  actions: [Icon(Icons.refresh)],
                ),
              ),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.arrow_back), findsOneWidget);
        expect(find.byIcon(Icons.refresh), findsOneWidget);
      });
    }
  }
}
