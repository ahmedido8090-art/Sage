import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sage/models/bella_data.dart';
import 'package:sage/services/weekly_summary.dart';
import 'package:sage/theme/app_theme.dart';
import 'package:sage/widgets/state_copy.dart';
import 'package:sage/widgets/weekly_summary_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 3, 10, 20);
  WellnessSession s(int offset, int min) => WellnessSession(
      type: 'walking',
      date: DateTime(2026, 3, 10 + offset, 9),
      durationMinutes: min);

  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('${dark ? 'dark' : 'light'} ${scale}x: with data and without',
          (tester) async {
        SharedPreferences.setMockInitialValues({});
        GoogleFonts.config.allowRuntimeFetching = false;
        await ThemeController.setDark(dark);
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);

        final withData = WeeklySummary.compute(
          sessions: [for (var i = 0; i < 5; i++) s(-i, 12), s(-8, 30)],
          checkins: [CheckinEntry(time: now, mood: 4, stress: 2, energy: 4)],
          sleep: const [],
          now: now,
        );
        final empty = WeeklySummary.compute(
            sessions: const [], checkins: const [], sleep: const [], now: now);

        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(
              size: const Size(320, 900), textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            theme: dark ? SageTheme.dark : SageTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(children: [
                  WeeklySummaryCard(summary: withData),
                  WeeklySummaryCard(summary: empty),
                ]),
              ),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        expect(find.text('Your week'), findsOneWidget);
        expect(find.text('Active days'), findsOneWidget);
        // The empty card invites rather than shows zeros.
        final inviting = [
          for (var i = 0; i < 3; i++)
            StateCopy.empty(StateTopic.insights, variant: i).title,
        ];
        expect(inviting.any((t) => find.text(t).evaluate().isNotEmpty), isTrue);
      });
    }
  }
}
