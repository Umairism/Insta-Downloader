# Media Downloader 🚀

A modern, universal Android media downloader built with **Flutter**, **Kotlin**, **yt-dlp**, and **FFmpegKit**.

Designed with a **headless, zero-interaction share workflow**: watch any video, tap the Android **Share** button, select **Media Downloader**, and the video downloads automatically in the background without launching the UI.

---

## ✨ Features

- **Headless Share Sheet Workflow**:
  - Automatically begins downloading as soon as you tap **Share ➔ Media Downloader**.
  - A lightweight transparent `ShareHandlerActivity` catches the intent and finishes immediately, leaving you right in your original app.
- **Universal yt-dlp Extraction**:
  - Supports any public video URL (YouTube, Instagram Reels, TikTok, Twitter/X, and hundreds more).
  - Powered by embedded Python 3.14 via Chaquopy and official `yt-dlp`.
  - Automatically selects the highest available source quality without upscaling (`bestvideo*+bestaudio/best`).
- **Selective FFmpeg Merging**:
  - FFmpeg runs **only when required** (e.g. merging separate video and audio streams).
  - Automatically applies `-movflags +faststart` for instant web and local playback.
- **Background Foreground Service & Sequential Queue**:
  - Uses an Android-compliant Foreground Service with persistent progress notifications.
  - Thread-safe sequential queue: multiple shared URLs are queued and processed one after another.
  - Clean private temporary storage; cache is completely purged upon completion or cancellation.
- **Android MediaStore Scoped Storage**:
  - Automatically publishes media directly to `Movies/Media Downloader/`.
  - Completion notifications feature direct `ACTION_VIEW` intents with `FLAG_GRANT_READ_URI_PERMISSION` to play media immediately.
- **Production-Ready Flutter Dashboard**:
  - **Downloaded Media Library**: Browse all downloaded videos on device storage with file sizes, dates, and durations.
  - **Direct Playback & Delete**: Play in default video players or permanently delete with confirmation dialogs.
  - **Manual Downloader**: Paste links directly with clipboard auto-paste detection.
  - **Dynamic Theme**: Modern dark mode with deep midnight surfaces, cyan/indigo gradients, and Material 3 design.
- **Modern Android Compatibility**:
  - Fully compatible with **Android 10 through Android 15+** (`arm64-v8a` and `x86_64`).
  - Packaged with 16KB page size compatibility for modern Android kernels.

---

## 🏗 Architecture

```text
User watches media (Instagram, YouTube, etc.)
               ↓
        Android Share
               ↓
    ShareHandlerActivity (Headless)
               ↓
  Foreground DownloadService (Queue)
               ↓
       Python / yt-dlp
               ↓
   FFmpegKit (when merge required)
               ↓
       Private App Cache
               ↓
   MediaStore (Movies/Media Downloader/)
               ↓
  Completion Notification & Media Library
```

---

## 📱 Screenshots & UI

- **Media Library**: View, play, and delete downloaded videos directly from the home screen.
- **Active Download Card**: Real-time progress bar, percentage, speed, and phase indicator (`Validating`, `Downloading`, `Merging`, `Completed`).
- **Manual Input Bar**: Fast link entry with one-tap clipboard paste.

---

## 🛠 Prerequisites & Tech Stack

- **Flutter**: 3.27+ (Dart 3.x)
- **Android SDK**: Platform 34-36 (Target SDK 36, Min SDK 24)
- **NDK**: 28+
- **Chaquopy**: 17.0.0 (Python 3.14)
- **FFmpegKit**: `dev.ffmpegkit-maintained:ffmpeg-kit-full:6.0.3`
- **Gradle**: 9.3.1 + Android Gradle Plugin 9.1.0

---

## 🚀 Building & Installation

### 1. Clone Repository
```bash
git clone https://github.com/Umairism/Insta-Downloader.git
cd Insta-Downloader
```

### 2. Install Flutter Dependencies
```bash
flutter pub get
```

### 3. Build Release APK
```bash
flutter build apk --release
# or using gradle directly
cd android && ./gradlew assembleRelease
```
The output APK will be located at:
```text
build/app/outputs/flutter-apk/app-release.apk
```

### 4. Install onto Device
```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

---

## 🧪 Testing

Run all unit and widget tests:
```bash
flutter test
```

Analyze code health:
```bash
flutter analyze
```

---

## ⚖️ License & Disclaimer

This software is for personal and educational use. Please respect copyright laws and the terms of service of the content platforms you interact with. Do not use this tool to bypass DRM, access restricted/private content, or infringe upon intellectual property rights.
