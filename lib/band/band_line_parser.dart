// band/band_line_parser.dart
//
// Reads one line of the band's text stream into numbers. The band's firmware
// has used two key styles, `HR:72,ST:1234,...` and `BPM:72,STEPS:1234,IR:...`,
// so both are accepted, with any case and spacing. Keys it does not use (IR,
// AX, AY, AZ, GX, GY, GZ) are ignored.
class BandLine {
  final int? heartRate;
  final int? steps;
  const BandLine({this.heartRate, this.steps});

  bool get isEmpty => heartRate == null && steps == null;
}

BandLine parseBandLine(String line) {
  int? heartRate;
  int? steps;
  for (final part in line.split(',')) {
    final kv = part.split(':');
    if (kv.length != 2) continue;
    final key = kv[0].trim().toUpperCase();
    final value = int.tryParse(kv[1].trim());
    if (key == 'HR' || key == 'BPM') heartRate = value;
    if (key == 'ST' || key == 'STEPS') steps = value;
  }
  return BandLine(heartRate: heartRate, steps: steps);
}
