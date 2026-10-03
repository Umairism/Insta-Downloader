import 'package:flutter/material.dart';
import 'package:insta_downlaader/models/download_task.dart';

class DownloadProgressView extends StatelessWidget {
  const DownloadProgressView({
    super.key,
    required this.event,
    this.onCancel,
    this.onOpen,
  });

  final DownloadEvent event;
  final VoidCallback? onCancel;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    if (event.phase == DownloadPhase.idle) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final percent = event.percent;
    final hasPercent = percent != null;
    final isError = event.phase == DownloadPhase.error;
    final isCompleted = event.phase == DownloadPhase.completed;
    final isCancelled = event.phase == DownloadPhase.cancelled;
    final isWorking = !isError && !isCompleted && !isCancelled;

    Color accentColor = const Color(0xFF6366F1);
    if (isCompleted) accentColor = const Color(0xFF10B981);
    if (isError) accentColor = const Color(0xFFEF4444);
    if (isCancelled) accentColor = Colors.orangeAccent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141C2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: isDark ? 0.15 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _phaseIcon(event.phase),
                  size: 20,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusLabel(event),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (event.message != null &&
                        event.message!.isNotEmpty &&
                        !isCompleted)
                      Text(
                        event.message!,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (hasPercent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${percent.round()}%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ),
            ],
          ),

          // Progress indicator
          if (isWorking) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: hasPercent ? (percent / 100).clamp(0.0, 1.0) : null,
                minHeight: 7,
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              ),
            ),
          ],

          // Bytes information
          if (event.downloadedBytes != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _sizeLine(event.downloadedBytes!, event.totalBytes),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ],

          // Completed or error action buttons
          if (isCompleted && onOpen != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onOpen,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text(
                  'Play Video',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],

          if (isWorking && onCancel != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                onPressed: onCancel,
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('Cancel Download', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _phaseIcon(DownloadPhase phase) {
    switch (phase) {
      case DownloadPhase.validating:
        return Icons.search_rounded;
      case DownloadPhase.queued:
        return Icons.schedule_rounded;
      case DownloadPhase.preparing:
      case DownloadPhase.fetching:
        return Icons.cloud_download_outlined;
      case DownloadPhase.downloading:
        return Icons.downloading_rounded;
      case DownloadPhase.processing:
        return Icons.auto_mode_rounded;
      case DownloadPhase.saving:
        return Icons.save_alt_rounded;
      case DownloadPhase.completed:
        return Icons.check_circle_rounded;
      case DownloadPhase.cancelled:
        return Icons.cancel_rounded;
      case DownloadPhase.error:
        return Icons.error_outline_rounded;
      case DownloadPhase.idle:
        return Icons.circle_outlined;
    }
  }

  static String _statusLabel(DownloadEvent event) {
    switch (event.phase) {
      case DownloadPhase.validating:
        return 'Validating link...';
      case DownloadPhase.queued:
        return event.queueSize != null && event.queueSize! > 0
            ? 'In Queue (#${event.queueSize})'
            : 'Queued';
      case DownloadPhase.preparing:
        return 'Preparing extraction...';
      case DownloadPhase.fetching:
        return 'Analyzing media streams...';
      case DownloadPhase.downloading:
        return 'Downloading media...';
      case DownloadPhase.processing:
        return 'Merging video & audio streams...';
      case DownloadPhase.saving:
        return 'Saving to MediaStore...';
      case DownloadPhase.completed:
        return 'Download Complete!';
      case DownloadPhase.cancelled:
        return 'Download Cancelled';
      case DownloadPhase.error:
        return event.message ?? 'Download failed';
      case DownloadPhase.idle:
        return '';
    }
  }

  static String _sizeLine(int downloaded, int? total) {
    if (total == null || total <= 0) {
      return _formatBytes(downloaded);
    }
    return '${_formatBytes(downloaded)} / ${_formatBytes(total)}';
  }

  static String _formatBytes(int bytes) {
    const mb = 1024 * 1024;
    const kb = 1024;
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    }
    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}
