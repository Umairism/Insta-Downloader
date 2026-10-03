import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:insta_downlaader/models/download_task.dart';
import 'package:insta_downlaader/services/downloader_service.dart';
import 'package:insta_downlaader/services/share_intent_service.dart';

class FakeDownloaderPlatform implements DownloaderPlatform {
  FakeDownloaderPlatform({this.initialUrl, this.startResult});

  final String? initialUrl;
  final Map<dynamic, dynamic>? startResult;
  final eventsController = StreamController<DownloadEvent>.broadcast(sync: true);
  int startCount = 0;
  int cancelCount = 0;
  String? lastUrl;
  String? openedUri;
  bool failStart = false;
  String? startErrorCode;

  @override
  Stream<DownloadEvent> events() => eventsController.stream;

  @override
  Future<Map<dynamic, dynamic>> startDownload(String url) async {
    startCount += 1;
    lastUrl = url;
    if (failStart) {
      return {
        'ok': false,
        'code': startErrorCode ?? 'PROCESS',
        'message': 'The downloader could not process this media.',
      };
    }
    return startResult ?? {'ok': true};
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
    eventsController.add(
      const DownloadEvent(
        type: 'state',
        phase: DownloadPhase.cancelled,
        message: 'Download was cancelled.',
      ),
    );
  }

  @override
  Future<String?> getInitialSharedUrl() async => initialUrl;

  @override
  Future<void> openFile(String uri) async {
    openedUri = uri;
  }

  @override
  Future<List<Map<dynamic, dynamic>>> getDownloadedMedia() async => [];

  @override
  Future<bool> deleteMedia(String uri) async => true;
}

void main() {
  test('Share intent populates the captured Instagram URL', () async {
    final platform = FakeDownloaderPlatform(
      initialUrl:
          'Look at this https://www.instagram.com/reel/ShareTest123/',
    );
    final downloader = DownloaderService(platform: platform);
    final share = ShareIntentService(downloader);
    final received = <String>[];
    final sub = share.urls.listen(received.add);

    await share.start();
    await Future<void>.delayed(Duration.zero);

    expect(received, contains('https://www.instagram.com/reel/ShareTest123/'));

    platform.eventsController.add(
      const DownloadEvent(
        type: 'share',
        url: 'https://www.instagram.com/p/AnotherPost/',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(received, contains('https://www.instagram.com/p/AnotherPost/'));

    await sub.cancel();
    share.dispose();
    downloader.dispose();
  });

  test('invalid URL never starts the native downloader', () async {
    final platform = FakeDownloaderPlatform();
    final downloader = DownloaderService(platform: platform);
    final error = await downloader.download('not-a-valid-url');
    expect(error, 'Invalid HTTP/HTTPS URL.');
    expect(platform.startCount, 0);
    downloader.dispose();
  });

  test('unavailable media surfaces a mapped error from the platform', () async {
    final platform = FakeDownloaderPlatform()
      ..failStart = true
      ..startErrorCode = 'UNAVAILABLE';
    final downloader = DownloaderService(platform: platform);
    final error = await downloader.download(
      'https://www.instagram.com/reel/Missing/',
    );
    expect(error, isNotNull);
    expect(platform.startCount, 1);
    downloader.dispose();
  });

  test('cancellation is forwarded to the platform', () async {
    final platform = FakeDownloaderPlatform();
    final downloader = DownloaderService(platform: platform);
    final events = <DownloadEvent>[];
    downloader.startListening();
    final sub = downloader.events.listen(events.add);
    await downloader.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(platform.cancelCount, 1);
    expect(events.single.phase, DownloadPhase.cancelled);
    await sub.cancel();
    downloader.dispose();
  });
}

/// Instagram live download coverage lives in [integration_download_test.dart]
/// and is skipped in ordinary unit test runs.
