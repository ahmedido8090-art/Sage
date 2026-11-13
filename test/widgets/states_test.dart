import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sage/theme/app_theme.dart';
import 'package:sage/utils/friendly_error.dart';
import 'package:sage/widgets/sage_button.dart';
import 'package:sage/widgets/sage_illustration.dart';
import 'package:sage/widgets/sage_skeleton.dart';
import 'package:sage/widgets/sage_states.dart';
import 'package:sage/widgets/state_copy.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required bool dark,
  double width = 320,
  double textScale = 1.0,
}) async {
  await ThemeController.setDark(dark);
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(
        size: Size(width, 900), textScaler: TextScaler.linear(textScale)),
    child: MaterialApp(
      theme: dark ? SageTheme.dark : SageTheme.light,
      home: Scaffold(
        backgroundColor: SageColors.linen,
        body: SingleChildScrollView(child: child),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('copy', () {
    const guilt = [
      'lazy',
      'fail',
      'disappoint',
      'you missed',
      'you forgot',
      'you haven\'t',
      'should have',
      'behind',
      'give up',
      'shame',
      'guilt',
      'neglect',
      'must',
    ];

    test('is warm and never blaming', () {
      for (final t in StateCopy.all()) {
        final text = '${t.title} ${t.message}'.toLowerCase();
        for (final w in guilt) {
          expect(text.contains(w), isFalse, reason: '"$w" in "$text"');
        }
        expect(t.title.length, lessThanOrEqualTo(48), reason: t.title);
        expect(t.message.length, lessThanOrEqualTo(120), reason: t.message);
      }
    });

    test('every topic has variety and rotates', () {
      for (final topic in StateTopic.values) {
        expect(StateCopy.count(topic), greaterThanOrEqualTo(3));
        final titles = {
          for (var i = 0; i < StateCopy.count(topic); i++)
            StateCopy.empty(topic, variant: i).title,
        };
        expect(titles.length, StateCopy.count(topic), reason: topic.name);
      }
    });
  });

  group('humanizeError', () {
    test('never leaks raw exception text', () {
      final errors = <Object>[
        TimeoutException('boom 0xDEADBEEF'),
        const FormatException('Unexpected character at 12'),
        PlatformException(
            code: 'x', message: 'permission denied at /data/user/0'),
        const FileSystemException('disk full', '/data/user/0/sage'),
        StateError('Bad state: Hive box closed'),
        Exception('RFCOMM socket closed: bluetooth gatt 133'),
        'plain string failure',
      ];
      for (final e in errors) {
        final f = humanizeError(e);
        final shown = '${f.title} ${f.message}'.toLowerCase();
        for (final leak in [
          '0x',
          '/data',
          'exception',
          'hive',
          'gatt',
          'rfcomm',
          'stateerror',
          'unexpected character'
        ]) {
          expect(shown.contains(leak), isFalse, reason: '$e leaked "$leak"');
        }
        expect(f.message, isNotEmpty);
      }
    });

    test('maps the common cases to the right kind', () {
      expect(humanizeError(TimeoutException('x')).kind, ErrorKind.timeout);
      expect(humanizeError(const FormatException('x')).kind, ErrorKind.data);
      expect(humanizeError(Exception('Bluetooth connect failed')).kind,
          ErrorKind.band);
      expect(humanizeError(null).kind, ErrorKind.generic);
    });
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    group('$mode widgets at 320px and large text', () {
      testWidgets('EmptyState renders and its action works', (tester) async {
        var taps = 0;
        await _pump(
            tester,
            EmptyState.topic(StateTopic.water,
                art: SageArt.water,
                actionLabel: 'Add water',
                onAction: () => taps++,
                secondaryLabel: 'Maybe later',
                onSecondary: () {}),
            dark: dark,
            textScale: 1.6);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Add water'));
        expect(taps, 1);
      });

      testWidgets('ErrorState shows friendly words and retries',
          (tester) async {
        var retries = 0;
        await _pump(
            tester,
            ErrorState(
                error: Exception('Bluetooth gatt 133'),
                onRetry: () => retries++),
            dark: dark,
            textScale: 1.6);
        expect(find.textContaining('Exception'), findsNothing);
        expect(find.textContaining('gatt'), findsNothing);
        await tester.tap(find.text('Try again'));
        expect(retries, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('ErrorState while retrying is disabled and busy',
          (tester) async {
        var retries = 0;
        await _pump(
            tester, ErrorState(onRetry: () => retries++, retrying: true),
            dark: dark);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
        expect(retries, 0);
      });

      testWidgets('PermissionState: prompt, then settings once blocked',
          (tester) async {
        var allowed = 0, settings = 0;
        await _pump(
            tester,
            PermissionState(
                kind: PermissionKind.notifications,
                onAllow: () => allowed++,
                onOpenSettings: () => settings++,
                onNotNow: () {}),
            dark: dark,
            textScale: 1.6);
        await tester.tap(find.text('Allow'));
        expect(allowed, 1);

        await _pump(
            tester,
            PermissionState(
                kind: PermissionKind.notifications,
                blocked: true,
                onAllow: () => allowed++,
                onOpenSettings: () => settings++),
            dark: dark);
        expect(find.textContaining('Settings'), findsWidgets);
        await tester.tap(find.text('Open Settings'));
        expect(settings, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('StatusBanner renders every kind with an action',
          (tester) async {
        var taps = 0;
        await _pump(
            tester,
            Column(children: [
              for (final k in BannerKind.values)
                StatusBanner(
                    kind: k,
                    message: 'Showing your last 14 days, since nothing newer '
                        'has been logged yet.',
                    actionLabel: 'Log now',
                    onAction: () => taps++),
            ]),
            dark: dark,
            textScale: 1.5);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Log now').first);
        expect(taps, 1);
      });

      testWidgets('SageButton: ready, busy and disabled', (tester) async {
        var taps = 0;
        await _pump(
            tester,
            Column(children: [
              SageButton(label: 'Save', onPressed: () => taps++),
              const SageButton(label: 'Disabled', onPressed: null),
              SageButton(
                  label: 'Busy', onPressed: () => taps += 10, loading: true),
              SageButton(
                  label: 'Outlined',
                  style: SageButtonStyle.outlined,
                  onPressed: () => taps += 100),
            ]),
            dark: dark);
        await tester.tap(find.text('Save'));
        await tester.tap(find.text('Disabled'), warnIfMissed: false);
        await tester.tap(find.byType(CircularProgressIndicator),
            warnIfMissed: false);
        await tester.tap(find.text('Outlined'));
        expect(taps, 101); // busy and disabled never fire
        expect(tester.takeException(), isNull);
      });

      testWidgets('skeletons render in every shape', (tester) async {
        await _pump(
            tester,
            Column(children: [
              SageSkeleton.card(),
              SageSkeleton.list(),
              SageSkeleton.screen(),
            ]),
            dark: dark);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('illustrations stand still with reduced motion', (tester) async {
    await ThemeController.setDark(false);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        home: const Scaffold(
            body: SageIllustration(
                art: SageArt.leaf, motion: SageArtMotion.sway)),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    // A swaying illustration would hold a running ticker; this one must not.
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a swaying illustration animates and disposes cleanly',
      (tester) async {
    await ThemeController.setDark(true);
    await tester.pumpWidget(MaterialApp(
      home: const Scaffold(
          body:
              SageIllustration(art: SageArt.leaf, motion: SageArtMotion.sway)),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
