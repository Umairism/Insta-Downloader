import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:insta_downlaader/models/download_task.dart';
import 'package:insta_downlaader/models/media_item.dart';
import 'package:insta_downlaader/utils/url_utils.dart';

abstract class DownloaderPlatform {
  Stream<DownloadEvent> events();
  Future<Map<dynamic, dynamic>> startDownload(String url);
  Future<void> cancel();
  Future<String?> getInitialSharedUrl();
  Future<void> openFile(String uri);
  Future<List<Map<dynamic, dynamic>>> getDownloadedMedia();
  Future<bool> deleteMedia(String uri);
}

class MethodChannelDownloaderPlatform implements DownloaderPlatform {
  MethodChannelDownloaderPlatform({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methods = methodChannel ?? const MethodChannel('com.example.insta_downlaader/downloader'),
       _events = eventChannel ?? const EventChannel('com.example.insta_downlaader/events');

  final MethodChannel _methods;
  final EventChannel _events;

  @override
  Stream<DownloadEvent> events() {
    try {
      return _events.receiveBroadcastStream().map((event) {
        if (event is Map) {
          return DownloadEvent.fromMap(event);
        }
        return const DownloadEvent(type: 'state');
      }).handleError((error) {
        debugPrint('[Downloader] Event stream error: $error');
      });
    } catch (e) {
      debugPrint('[Downloader] Failed to receive event stream: $e');
      return const Stream.empty();
    }
  }

  @override
  Future<Map<dynamic, dynamic>> startDownload(String url) async {
    final result = await _methods.invokeMethod<Map<dynamic, dynamic>>('startDownload', {
      'url': url,
    });
    return result ?? {'ok': true};
  }

  @override
  Future<void> cancel() {
    return _methods.invokeMethod<void>('cancelDownload');
  }

  @override
  Future<String?> getInitialSharedUrl() {
    return _methods.invokeMethod<String>('getInitialSharedUrl');
  }

  @override
  Future<void> openFile(String uri) {
    return _methods.invokeMethod<void>('openFile', {'uri': uri});
  }

  @override
  Future<List<Map<dynamic, dynamic>>> getDownloadedMedia() async {
    try {
      final result = await _methods.invokeMethod<List<dynamic>>('getDownloadedMedia');
      if (result == null) return [];
      return result.whereType<Map<dynamic, dynamic>>().toList();
    } catch (e) {
      debugPrint('[Downloader] Failed to get downloaded media: $e');
      return [];
    }
  }

  @override
  Future<bool> deleteMedia(String uri) async {
    try {
      final result = await _methods.invokeMethod<Map<dynamic, dynamic>>('deleteMedia', {'uri': uri});
      return result?['ok'] == true;
    } catch (e) {
      debugPrint('[Downloader] Failed to delete media: $e');
      return false;
    }
  }
}

class DownloaderService {
  DownloaderService({DownloaderPlatform? platform})
    : _platform = platform ?? MethodChannelDownloaderPlatform();

  final DownloaderPlatform _platform;
  StreamSubscription<DownloadEvent>? _subscription;
  final _controller = StreamController<DownloadEvent>.broadcast();

  Stream<DownloadEvent> get events => _controller.stream;

  void startListening() {
    _subscription ??= _platform.events().listen(
      _controller.add,
      onError: (Object error, StackTrace stack) {
        debugPrint('[Downloader] Event channel error: $error');
      },
    );
  }

  Future<String?> consumeInitialSharedUrl() async {
    try {
      return await _platform.getInitialSharedUrl();
    } on PlatformException catch (error) {
      debugPrint('[Downloader] share lookup failed: ${error.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  String? validateUrl(String raw) {
    final extracted = UrlUtils.extractUrlFromShareText(raw) ?? raw.trim();
    if (!UrlUtils.isValidHttpUrl(extracted)) {
      return 'Invalid HTTP/HTTPS URL.';
    }
    return null;
  }

  Future<String?> download(String raw) async {
    debugPrint('[Downloader] Validating URL');
    final extracted = UrlUtils.extractUrlFromShareText(raw) ?? raw.trim();
    final error = validateUrl(extracted);
    if (error != null) return error;
    debugPrint('[Downloader] Starting yt-dlp');
    startListening();
    try {
      final result = await _platform.startDownload(extracted);
      if (result['ok'] == false) {
        return result['message']?.toString() ?? 'This post could not be downloaded.';
      }
      return null;
    } on MissingPluginException {
      return 'The downloader could not process this media.';
    } on PlatformException catch (error) {
      debugPrint('[Downloader] start failed: ${error.message}');
      return 'The downloader could not process this media.';
    }
  }

  Future<void> cancel() async {
    debugPrint('[Downloader] Cancel requested');
    try {
      await _platform.cancel();
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      debugPrint('[Downloader] cancel failed: ${error.message}');
    }
  }

  Future<void> openFile(String uri) => _platform.openFile(uri);

  Future<List<MediaItem>> getDownloadedMedia() async {
    final rawList = await _platform.getDownloadedMedia();
    return rawList.map((map) => MediaItem.fromMap(map)).toList();
  }

  Future<bool> deleteMedia(String uri) => _platform.deleteMedia(uri);

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _controller.close();
  }
}
