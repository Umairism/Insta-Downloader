class FilenameUtils {
  static final _illegal = RegExp(r'[\\/:*?"<>|\x00-\x1F]');

  static String sanitize(String raw, {String fallback = 'Media_video'}) {
    var name = raw.replaceAll('\\', '/').split('/').last;
    if (name.isEmpty || name == '.' || name == '..') {
      return fallback;
    }
    name = name.replaceAll('..', '_');
    name = name.replaceAll(_illegal, '_');
    name = name.trim().replaceAll(RegExp(r'^\.+|\.+$'), '');
    if (name.isEmpty || name == '.' || name == '..') {
      return fallback;
    }
    if (name.length > 80) {
      name = name.substring(0, 80);
    }
    return name;
  }

  static String timestampedName(DateTime now, {String prefix = 'Media'}) {
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}-${two(now.minute)}-${two(now.second)}';
    return '${prefix}_$stamp.mp4';
  }
}
