import 'dart:async';

import 'package:insta_downlaader/models/download_task.dart';
import 'package:insta_downlaader/services/downloader_service.dart';
import 'package:insta_downlaader/utils/url_utils.dart';

/// Surfaces Android ACTION_SEND text/plain URLs, including those received
/// before Flutter finished launching.
class ShareIntentService {
  ShareIntentService(this._downloader);

  final DownloaderService _downloader;
  final _urls = StreamController<String>.broadcast();

  Stream<String> get urls => _urls.stream;
  StreamSubscription<DownloadEvent>? _events;

  Future<void> start() async {
    _downloader.startListening();
    _events ??= _downloader.events.listen((event) {
      if (!event.isShare) return;
      final url = UrlUtils.extractUrlFromShareText(event.url ?? '') ?? event.url;
      if (url != null && url.isNotEmpty) {
        _urls.add(url);
      }
    });
    final initial = await _downloader.consumeInitialSharedUrl();
    if (initial != null && initial.isNotEmpty) {
      final url = UrlUtils.extractUrlFromShareText(initial) ?? initial;
      _urls.add(url);
    }
  }

  void dispose() {
    _events?.cancel();
    _urls.close();
  }
}
