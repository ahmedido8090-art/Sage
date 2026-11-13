import 'package:flutter_test/flutter_test.dart';
import 'package:sage/band/band_line_parser.dart';

void main() {
  test('reads the HR / ST format', () {
    final l =
        parseBandLine('HR:72,AX:100,AY:-20,AZ:9800,GX:1,GY:2,GZ:3,ST:1234');
    expect(l.heartRate, 72);
    expect(l.steps, 1234);
  });

  test('reads the BPM / STEPS format', () {
    final l = parseBandLine('STEPS:123,IR:50000,BPM:75');
    expect(l.heartRate, 75);
    expect(l.steps, 123);
  });

  test('is case and spacing tolerant', () {
    final l = parseBandLine(' bpm : 64 , steps: 9 ');
    expect(l.heartRate, 64);
    expect(l.steps, 9);
  });

  test('a line with only one of the two still gives that one', () {
    expect(parseBandLine('HR:80').heartRate, 80);
    expect(parseBandLine('HR:80').steps, isNull);
    expect(parseBandLine('ST:5').steps, 5);
    expect(parseBandLine('ST:5').heartRate, isNull);
  });

  test('ignores keys it does not use and malformed pieces', () {
    final l = parseBandLine('IR:50000,AX:1,garbage,BPM:,STEPS:abc,HR:70');
    expect(l.heartRate, 70);
    expect(l.steps, isNull);
  });

  test('an empty or junk line is empty, never a made-up value', () {
    expect(parseBandLine('').isEmpty, isTrue);
    expect(parseBandLine('hello world').isEmpty, isTrue);
    expect(parseBandLine('::,,:').isEmpty, isTrue);
  });

  test('a later duplicate key wins, like a stream would update', () {
    expect(parseBandLine('HR:60,BPM:90').heartRate, 90);
  });
}
