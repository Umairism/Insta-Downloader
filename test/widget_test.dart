
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insta_downlaader/app/app.dart';
import 'package:insta_downlaader/models/download_task.dart';
import 'package:insta_downlaader/screens/home_screen.dart';
import 'package:insta_downlaader/services/downloader_service.dart';

import 'downloader_service_test.dart';

void main() {
  testWidgets('home screen shows URL field and download button', (tester) async {
    final platform = FakeDownloaderPlatform();
    final downloader = DownloaderService(platform: platform);
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(downloader: downloader)),
    );
    await tester.pump();

    expect(find.text('Media Downloader'), findsOneWidget);
    expect(find.text('Download Media'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    downloader.dispose();
  });

  testWidgets('shared URL appears in the text field', (tester) async {
    final platform = FakeDownloaderPlatform(
      initialUrl: 'https://www.instagram.com/reel/FromShare/',
    );
    final downloader = DownloaderService(platform: platform);
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(downloader: downloader)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('https://www.instagram.com/reel/FromShare/'), findsOneWidget);
    downloader.dispose();
  });

  testWidgets('InstagramDownloaderApp builds', (tester) async {
    await tester.pumpWidget(const InstagramDownloaderApp());
    await tester.pump();
    expect(find.text('Media Downloader'), findsOneWidget);
  });

  testWidgets('progress event updates status text', (tester) async {
    final platform = FakeDownloaderPlatform();
    final downloader = DownloaderService(platform: platform);
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(downloader: downloader)),
    );
    await tester.pump();

    platform.eventsController.add(
      const DownloadEvent(
        type: 'state',
        phase: DownloadPhase.downloading,
        percent: 67,
        downloadedBytes: 24300000,
        totalBytes: 36100000,
        message: 'Downloading',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Downloading media...'), findsOneWidget);
    expect(find.text('67%'), findsOneWidget);
    expect(find.text('Cancel Download'), findsOneWidget);

    downloader.dispose();
  });
}
