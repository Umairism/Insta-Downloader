class MediaItem {
  const MediaItem({
    required this.id,
    required this.displayName,
    required this.size,
    required this.dateAdded,
    required this.duration,
    required this.uri,
    required this.mimeType,
  });

  factory MediaItem.fromMap(Map<dynamic, dynamic> map) {
    return MediaItem(
      id: map['id']?.toString() ?? '',
      displayName: map['displayName']?.toString() ?? 'Media Video',
      size: (map['size'] as num?)?.toInt() ?? 0,
      dateAdded: (map['dateAdded'] as num?)?.toInt() ?? 0,
      duration: (map['duration'] as num?)?.toInt() ?? 0,
      uri: map['uri']?.toString() ?? '',
      mimeType: map['mimeType']?.toString() ?? 'video/mp4',
    );
  }

  final String id;
  final String displayName;
  final int size;
  final int dateAdded;
  final int duration;
  final String uri;
  final String mimeType;

  String get formattedSize {
    if (size <= 0) return 'Unknown size';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedDate {
    if (dateAdded <= 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(dateAdded * 1000);
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';

    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String get formattedDuration {
    if (duration <= 0) return '';
    final totalSeconds = duration ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remMinutes = minutes % 60;
      return '$hours:${remMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get cleanTitle {
    var title = displayName;
    if (title.endsWith('.mp4') || title.endsWith('.mkv') || title.endsWith('.webm')) {
      title = title.substring(0, title.lastIndexOf('.'));
    }
    // Remove date suffix like _2026-10-03_15-35-16 if present
    final dateRegex = RegExp(r'_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$');
    title = title.replaceAll(dateRegex, '');
    return title.isEmpty ? displayName : title;
  }
}
