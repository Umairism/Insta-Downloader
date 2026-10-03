import 'package:flutter_test/flutter_test.dart';

/// These cases require a device/emulator, network, and a currently public
/// Instagram URL. They are skipped in CI so the suite does not depend on
/// Instagram remaining reachable.
void main() {
  test(
    'successful public Reel download',
    () async {},
    skip: 'Integration: run on device against a public Reel URL.',
  );

  test(
    'network failure is reported cleanly',
    () async {},
    skip: 'Integration: disable networking on device and start a download.',
  );

  test(
    'FFmpeg processing failure is reported cleanly',
    () async {},
    skip: 'Integration: feed an unreadable temp file into the merger.',
  );
}
