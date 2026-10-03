import 'dart:async';

import 'package:flutter/material.dart';
import 'package:insta_downlaader/models/download_task.dart';
import 'package:insta_downlaader/models/media_item.dart';
import 'package:insta_downlaader/services/downloader_service.dart';
import 'package:insta_downlaader/services/share_intent_service.dart';
import 'package:insta_downlaader/widgets/download_progress.dart';
import 'package:insta_downlaader/widgets/media_card.dart';
import 'package:insta_downlaader/widgets/url_input.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.downloader});

  final DownloaderService? downloader;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final DownloaderService _downloader;
  late final ShareIntentService _shareIntent;
  late final TextEditingController _urlController;
  late final StreamSubscription<DownloadEvent> _downloadSub;
  late final StreamSubscription<String> _shareSub;

  DownloadEvent _event = const DownloadEvent(type: 'state');
  bool _busy = false;

  List<MediaItem> _mediaList = [];
  bool _isLoadingMedia = true;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _downloader = widget.downloader ?? DownloaderService();
    _shareIntent = ShareIntentService(_downloader);
    _downloader.startListening();

    _downloadSub = _downloader.events.listen((event) {
      if (event.isShare) return;
      setState(() {
        _event = event;
        _busy = event.phase == DownloadPhase.validating ||
            event.phase == DownloadPhase.queued ||
            event.phase == DownloadPhase.preparing ||
            event.phase == DownloadPhase.fetching ||
            event.phase == DownloadPhase.downloading ||
            event.phase == DownloadPhase.processing ||
            event.phase == DownloadPhase.saving;
      });

      // When a download finishes, refresh media list automatically
      if (event.phase == DownloadPhase.completed) {
        _loadMedia();
      }
    });

    _shareSub = _shareIntent.urls.listen((url) {
      setState(() {
        _urlController.text = url;
      });
    });

    unawaited(_shareIntent.start());
    _loadMedia();
  }

  @override
  void dispose() {
    _downloadSub.cancel();
    _shareSub.cancel();
    _shareIntent.dispose();
    if (widget.downloader == null) {
      _downloader.dispose();
    }
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadMedia() async {
    setState(() {
      _isLoadingMedia = true;
    });
    final media = await _downloader.getDownloadedMedia();
    if (!mounted) return;
    setState(() {
      _mediaList = media;
      _isLoadingMedia = false;
    });
  }

  Future<void> _download() async {
    final text = _urlController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter or paste a valid video URL'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final error = await _downloader.download(text);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _event = DownloadEvent(
          type: 'state',
          phase: DownloadPhase.error,
          message: error,
        );
      });
    } else {
      setState(() {
        _busy = true;
        _event = const DownloadEvent(
          type: 'state',
          phase: DownloadPhase.validating,
          message: 'Validating URL...',
        );
      });
    }
  }

  Future<void> _cancel() => _downloader.cancel();

  Future<void> _open([String? specificUri]) async {
    final uri = specificUri ?? _event.savedUri;
    if (uri == null || uri.isEmpty) return;
    await _downloader.openFile(uri);
  }

  Future<void> _confirmDelete(MediaItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161F30),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          title: Row(
            children: const [
              Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24),
              SizedBox(width: 8),
              Text(
                'Delete Video?',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to permanently delete this media from storage?',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  item.cleanTitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      final success = await _downloader.deleteMedia(item.uri);
      if (!mounted) return;
      if (success) {
        setState(() {
          _mediaList.removeWhere((element) => element.id == item.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video deleted from device'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete file'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0E1A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF06B6D4)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.download_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Media Downloader',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Library',
            onPressed: _loadMedia,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadMedia,
        color: const Color(0xFF6366F1),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Manual URL Input Box
                    UrlInput(
                      controller: _urlController,
                      enabled: !_busy,
                      onSubmitted: (_) => _download(),
                    ),
                    const SizedBox(height: 10),

                    // Download Action Button
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _busy ? null : _download,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_busy) ...[
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Processing...',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ] else ...[
                              const Icon(Icons.cloud_download_rounded, color: Colors.white),
                              const SizedBox(width: 8),
                              const Text(
                                'Download Media',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Active Download / Queue Banner
                    if (_event.phase != DownloadPhase.idle) ...[
                      DownloadProgressView(
                        event: _event,
                        onCancel: _busy ? _cancel : null,
                        onOpen: _event.phase == DownloadPhase.completed ? () => _open() : null,
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Section Title: Downloaded Media Library
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Media Library',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_mediaList.length}',
                                style: const TextStyle(
                                  color: Color(0xFF818CF8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Movies/Media Downloader',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white38 : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            // Media Items List or Empty State
            if (_isLoadingMedia && _mediaList.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF6366F1),
                  ),
                ),
              )
            else if (_mediaList.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.video_library_outlined,
                          size: 56,
                          color: Color(0xFF818CF8),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'No Downloaded Media',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Share a video from YouTube, Instagram, or any app, or paste a link above to download.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white54 : Colors.black54,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = _mediaList[index];
                      return MediaCard(
                        item: item,
                        onTap: () => _open(item.uri),
                        onDelete: () => _confirmDelete(item),
                      );
                    },
                    childCount: _mediaList.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
