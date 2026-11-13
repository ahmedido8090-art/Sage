import 'package:flutter/material.dart' show Material, MaterialApp, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sage/utils/page_transitions.dart';
import 'package:sage/utils/soften_caps.dart';
import 'package:sage/widgets/animated_number.dart';
import 'package:sage/widgets/pressable.dart';
import 'package:sage/widgets/reveal.dart';

Widget _host(Widget child, {required bool reduce}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    );

void main() {
  group('Reveal', () {
    testWidgets('fades in over time normally', (tester) async {
      await tester
          .pumpWidget(_host(const Reveal(child: Text('hi')), reduce: false));
      await tester.pump();
      final start = tester
          .widget<FadeTransition>(find.byType(FadeTransition).last)
          .opacity
          .value;
      await tester.pump(const Duration(milliseconds: 600));
      final end = tester
          .widget<FadeTransition>(find.byType(FadeTransition).last)
          .opacity
          .value;
      expect(start, lessThan(1));
      expect(end, 1);
    });

    testWidgets('is fully visible straight away with reduced motion',
        (tester) async {
      await tester
          .pumpWidget(_host(const Reveal(child: Text('hi')), reduce: true));
      await tester.pump(); // post-frame callback
      final fade =
          tester.widget<FadeTransition>(find.byType(FadeTransition).last);
      expect(fade.opacity.value, 1);
    });
  });

  group('AnimatedNumber', () {
    Future<String> shownAfterChange(WidgetTester tester, bool reduce) async {
      Widget build(int v) => _host(AnimatedNumber(value: v), reduce: reduce);
      await tester.pumpWidget(build(10));
      await tester.pumpWidget(build(100));
      await tester.pump(const Duration(milliseconds: 50));
      return (tester.widget<Text>(find.byType(Text)).data)!;
    }

    testWidgets('counts up mid-way normally', (tester) async {
      final shown = int.parse(await shownAfterChange(tester, false));
      expect(shown, inInclusiveRange(10, 99));
      await tester.pumpAndSettle();
    });

    testWidgets('jumps to the value with reduced motion', (tester) async {
      expect(await shownAfterChange(tester, true), '100');
    });
  });

  testWidgets('Pressable does not shrink on press with reduced motion',
      (tester) async {
    await tester.pumpWidget(_host(
        Pressable(onTap: () {}, child: const SizedBox(width: 80, height: 80)),
        reduce: true));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Pressable)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);
    await gesture.up();
  });

  for (final reduce in [true, false]) {
    testWidgets(
        reduce
            ? 'route transitions return the page untouched with reduced motion'
            : 'route transitions animate normally', (tester) async {
      const page = Text('next page');
      late Widget built;
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Builder(builder: (context) {
          for (final route in [
            slideUpRoute<void>(page),
            slideRightRoute<void>(page),
            fadeRoute<void>(page),
          ]) {
            built = (route as PageRouteBuilder<void>).transitionsBuilder(
              context,
              const AlwaysStoppedAnimation<double>(0.3),
              const AlwaysStoppedAnimation<double>(0),
              page,
            );
            expect(identical(built, page), reduce);
          }
          return const SizedBox();
        }),
      ));
    });
  }

  group('softenCaps', () {
    test('turns shouting into sentence case', () {
      expect(softenCaps('WIND-DOWN TIPS'), 'Wind-down tips');
      expect(softenCaps('CHRONIC CONDITIONS (OPTIONAL)'),
          'Chronic conditions (optional)');
    });

    test('leaves normal text alone', () {
      expect(softenCaps('Fitly plan'), 'Fitly plan');
      expect(softenCaps('Sleep sounds'), 'Sleep sounds');
      expect(softenCaps('A'), 'A');
      expect(softenCaps('HR'), 'Hr'); // two caps count as shouting
      expect(softenCaps(''), '');
    });
  });
}
