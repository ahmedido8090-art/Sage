import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sage/band/band_access.dart';

class _Fake implements BandPermissionSource {
  var scan = PermissionStatus.denied;
  var connect = PermissionStatus.denied;
  var afterRequestScan = PermissionStatus.granted;
  var afterRequestConnect = PermissionStatus.granted;
  var requested = 0;

  @override
  Future<(PermissionStatus, PermissionStatus)> status() async =>
      (scan, connect);

  @override
  Future<(PermissionStatus, PermissionStatus)> request() async {
    requested++;
    scan = afterRequestScan;
    connect = afterRequestConnect;
    return (scan, connect);
  }
}

void main() {
  group('bandAccessFrom', () {
    test('needs both permissions', () {
      expect(bandAccessFrom(PermissionStatus.granted, PermissionStatus.granted),
          BandAccess.granted);
      expect(bandAccessFrom(PermissionStatus.granted, PermissionStatus.denied),
          BandAccess.askable);
      expect(bandAccessFrom(PermissionStatus.denied, PermissionStatus.granted),
          BandAccess.askable);
    });

    test('permanent denial of either one is blocked', () {
      expect(
          bandAccessFrom(
              PermissionStatus.granted, PermissionStatus.permanentlyDenied),
          BandAccess.blocked);
      expect(
          bandAccessFrom(
              PermissionStatus.permanentlyDenied, PermissionStatus.granted),
          BandAccess.blocked);
      expect(
          bandAccessFrom(PermissionStatus.restricted, PermissionStatus.granted),
          BandAccess.blocked);
    });
  });

  group('bandAccess', () {
    test('iOS needs nothing: the system prompts by itself', () async {
      final f = _Fake();
      expect(await bandAccess(ask: true, source: f, isAndroid: false),
          BandAccess.granted);
      expect(f.requested, 0);
    });

    test('Android asks when allowed to, and reports the result', () async {
      final f = _Fake();
      expect(await bandAccess(ask: true, source: f, isAndroid: true),
          BandAccess.granted);
      expect(f.requested, 1);
    });

    test('does not prompt when only checking', () async {
      final f = _Fake();
      expect(await bandAccess(ask: false, source: f, isAndroid: true),
          BandAccess.askable);
      expect(f.requested, 0);
    });

    test('a refusal that is final becomes blocked', () async {
      final f = _Fake()
        ..afterRequestScan = PermissionStatus.permanentlyDenied
        ..afterRequestConnect = PermissionStatus.permanentlyDenied;
      expect(await bandAccess(ask: true, source: f, isAndroid: true),
          BandAccess.blocked);
    });

    test('a simple refusal can be asked again', () async {
      final f = _Fake()
        ..afterRequestScan = PermissionStatus.denied
        ..afterRequestConnect = PermissionStatus.denied;
      expect(await bandAccess(ask: true, source: f, isAndroid: true),
          BandAccess.askable);
    });

    test('already granted never prompts', () async {
      final f = _Fake()
        ..scan = PermissionStatus.granted
        ..connect = PermissionStatus.granted;
      expect(await bandAccess(ask: true, source: f, isAndroid: true),
          BandAccess.granted);
      expect(f.requested, 0);
    });

    test('blocked is never re-prompted', () async {
      final f = _Fake()
        ..scan = PermissionStatus.permanentlyDenied
        ..connect = PermissionStatus.granted;
      expect(await bandAccess(ask: true, source: f, isAndroid: true),
          BandAccess.blocked);
      expect(f.requested, 0);
    });
  });
}
