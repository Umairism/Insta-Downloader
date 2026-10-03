enum DownloadPhase {
  idle,
  validating,
  queued,
  preparing,
  fetching,
  downloading,
  processing,
  saving,
  completed,
  cancelled,
  error,
}

class DownloadEvent {
  const DownloadEvent({
    required this.type,
    this.phase = DownloadPhase.idle,
    this.taskId,
    this.title,
    this.url,
    this.message,
    this.code,
    this.percent,
    this.downloadedBytes,
    this.totalBytes,
    this.savedPath,
    this.savedUri,
    this.queueSize,
  });

  final String type;
  final DownloadPhase phase;
  final String? taskId;
  final String? title;
  final String? url;
  final String? message;
  final String? code;
  final double? percent;
  final int? downloadedBytes;
  final int? totalBytes;
  final String? savedPath;
  final String? savedUri;
  final int? queueSize;

  bool get isShare => type == 'share';

  static DownloadPhase parsePhase(String? raw) {
    switch (raw) {
      case 'validating':
        return DownloadPhase.validating;
      case 'queued':
        return DownloadPhase.queued;
      case 'preparing':
        return DownloadPhase.preparing;
      case 'fetching':
        return DownloadPhase.fetching;
      case 'downloading':
        return DownloadPhase.downloading;
      case 'processing':
        return DownloadPhase.processing;
      case 'saving':
        return DownloadPhase.saving;
      case 'completed':
        return DownloadPhase.completed;
      case 'cancelled':
        return DownloadPhase.cancelled;
      case 'error':
        return DownloadPhase.error;
      default:
        return DownloadPhase.idle;
    }
  }

  factory DownloadEvent.fromMap(Map<dynamic, dynamic> map) {
    return DownloadEvent(
      type: map['type']?.toString() ?? 'state',
      phase: parsePhase(map['state']?.toString()),
      taskId: map['taskId']?.toString(),
      title: map['title']?.toString(),
      url: map['url']?.toString(),
      message: map['message']?.toString(),
      code: map['code']?.toString(),
      percent: (map['percent'] as num?)?.toDouble(),
      downloadedBytes: (map['downloadedBytes'] as num?)?.toInt(),
      totalBytes: (map['totalBytes'] as num?)?.toInt(),
      savedPath: map['savedPath']?.toString(),
      savedUri: map['savedUri']?.toString(),
      queueSize: (map['queueSize'] as num?)?.toInt(),
    );
  }
}
