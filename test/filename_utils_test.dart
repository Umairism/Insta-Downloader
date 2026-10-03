import 'package:flutter_test/flutter_test.dart';
import 'package:insta_downlaader/utils/filename_utils.dart';

void main() {
  group('FilenameUtils.sanitize', () {
    test('strips illegal filesystem characters', () {
      expect(
        FilenameUtils.sanitize(r'a/b\c:d*e?f"g<h>i|j'),
        'c_d_e_f_g_h_i_j',
      );
    });

    test('blocks path traversal', () {
      expect(FilenameUtils.sanitize('../../etc/passwd'), 'passwd');
      expect(FilenameUtils.sanitize('..'), 'Media_video');
      expect(FilenameUtils.sanitize('../..\\secret'), 'secret');
    });

    test('replaces reserved characters in a title', () {
      expect(FilenameUtils.sanitize('cool: video*?'), 'cool_ video__');
    });
  });

  test('timestampedName uses a stable pattern', () {
    final name = FilenameUtils.timestampedName(DateTime(2026, 10, 3, 12, 30, 45));
    expect(name, 'Media_2026-10-03_12-30-45.mp4');
  });
}
