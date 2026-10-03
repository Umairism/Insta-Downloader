import 'package:flutter_test/flutter_test.dart';
import 'package:insta_downlaader/utils/url_utils.dart';

void main() {
  group('UrlUtils.isValidHttpUrl', () {
    test('accepts valid HTTP/HTTPS URLs', () {
      expect(UrlUtils.isValidHttpUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), isTrue);
      expect(UrlUtils.isValidHttpUrl('https://instagram.com/reel/AbC123xyz/'), isTrue);
      expect(UrlUtils.isValidHttpUrl('http://example.com/video.mp4'), isTrue);
      expect(UrlUtils.isValidHttpUrl('https://tiktok.com/@user/video/12345'), isTrue);
    });

    test('rejects malformed or non-http URLs', () {
      expect(UrlUtils.isValidHttpUrl('not a url'), isFalse);
      expect(UrlUtils.isValidHttpUrl(''), isFalse);
      expect(UrlUtils.isValidHttpUrl('ftp://example.com/file'), isFalse);
    });
  });

  group('UrlUtils.isInstagramUrl (legacy)', () {
    test('accepts a Reel URL', () {
      expect(
        UrlUtils.isInstagramUrl('https://www.instagram.com/reel/AbC123xyz/'),
        isTrue,
      );
    });

    test('accepts a post URL', () {
      expect(
        UrlUtils.isInstagramUrl('https://www.instagram.com/p/AbC123xyz/'),
        isTrue,
      );
    });

    test('rejects an unrelated URL', () {
      expect(UrlUtils.isInstagramUrl('https://youtube.com/watch?v=abc'), isFalse);
    });
  });

  group('UrlUtils.extractUrlFromShareText', () {
    test('extracts any HTTP/HTTPS URL from share text', () {
      const ytText = 'Watch this: https://youtu.be/dQw4w9WgXcQ?si=test check it out';
      expect(
        UrlUtils.extractUrlFromShareText(ytText),
        'https://youtu.be/dQw4w9WgXcQ?si=test',
      );

      const igText = 'Check out this reel! https://www.instagram.com/reel/AbC123xyz/?igsh=xyz';
      expect(
        UrlUtils.extractUrlFromShareText(igText),
        'https://www.instagram.com/reel/AbC123xyz/?igsh=xyz',
      );
    });
  });
}
