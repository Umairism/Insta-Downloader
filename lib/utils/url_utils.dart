/// Universal media URL helpers. Shared text from Android is untrusted input.
class UrlUtils {
  static final _urlInText = RegExp(
    r'https?://[^\s<>"' "'" r']+',
    caseSensitive: false,
  );

  static String? extractUrlFromShareText(String text) {
    final matches = _urlInText.allMatches(text).map((match) {
      return match.group(0)!.replaceAll(RegExp(r'''[.,)\]'"']+$'''), '');
    }).toList();
    if (matches.isEmpty) {
      final trimmed = text.trim();
      return isValidHttpUrl(trimmed) ? trimmed : null;
    }
    return matches.first;
  }

  static bool isValidHttpUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return false;
    final parsed = Uri.tryParse(
      value.startsWith('http://') || value.startsWith('https://')
          ? value
          : 'https://$value',
    );
    if (parsed == null) return false;
    if (parsed.scheme != 'http' && parsed.scheme != 'https') return false;
    final host = parsed.host.toLowerCase();
    return host.isNotEmpty && host.contains('.');
  }

  @Deprecated('Use isValidHttpUrl instead')
  static bool isInstagramUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return false;
    final parsed = Uri.tryParse(
      value.startsWith('http://') || value.startsWith('https://')
          ? value
          : 'https://$value',
    );
    if (parsed == null) return false;
    if (parsed.scheme != 'http' && parsed.scheme != 'https') return false;
    final host = parsed.host.toLowerCase();
    return host == 'instagram.com' ||
        host.endsWith('.instagram.com') ||
        host == 'instagr.am' ||
        host.endsWith('.instagr.am');
  }
}
