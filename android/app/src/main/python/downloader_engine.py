"""yt-dlp extraction/download engine for Android (Chaquopy).

Invoked from Kotlin with explicit arguments. Never uses a shell.
"""

from __future__ import annotations

import json
import os
import sys
import traceback

UPDATE_DIR_ENV = "YTDLP_UPDATE_DIR"


def _prepare_sys_path() -> None:
    update_dir = os.environ.get(UPDATE_DIR_ENV)
    if update_dir and os.path.isdir(update_dir):
        if update_dir not in sys.path:
            sys.path.insert(0, update_dir)
            print("[Downloader] Using updated yt-dlp from", update_dir)


_prepare_sys_path()

import yt_dlp  # noqa: E402


class DownloadCancelled(Exception):
    pass


class EngineError(Exception):
    def __init__(self, code: str, message: str, detail: str = ""):
        super().__init__(message)
        self.code = code
        self.message = message
        self.detail = detail


def _log(message: str) -> None:
    print(f"[Downloader] {message}")


def _is_cancelled(checker) -> bool:
    if checker is None:
        return False
    try:
        if hasattr(checker, "is_cancelled"):
            return bool(checker.is_cancelled())
        return bool(checker())
    except Exception:
        return False


def _raise_if_cancelled(checker) -> None:
    if _is_cancelled(checker):
        raise DownloadCancelled("Download was cancelled.")


def _safe_int(value):
    try:
        if value is None:
            return None
        return int(value)
    except (TypeError, ValueError):
        return None


def _safe_float(value):
    try:
        if value is None:
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def _codec_present(value) -> bool:
    return value not in (None, "none", "None", "")


def _quality_tuple(fmt: dict) -> tuple:
    height = fmt.get("height") or 0
    width = fmt.get("width") or 0
    tbr = fmt.get("tbr") or fmt.get("vbr") or 0
    fps = fmt.get("fps") or 0
    filesize = fmt.get("filesize") or fmt.get("filesize_approx") or 0
    return (height, width, tbr, fps, filesize)


def _audio_quality_tuple(fmt: dict) -> tuple:
    abr = fmt.get("abr") or fmt.get("tbr") or 0
    filesize = fmt.get("filesize") or fmt.get("filesize_approx") or 0
    return (abr, filesize)


def _pick_formats(info: dict) -> tuple[list[str], bool]:
    """Return (format_ids, needs_merge) for the highest practical quality."""
    formats = [f for f in (info.get("formats") or []) if isinstance(f, dict) and f.get("format_id")]
    if not formats and info.get("url"):
        return ["best"], False

    video_only = [
        f
        for f in formats
        if _codec_present(f.get("vcodec")) and not _codec_present(f.get("acodec"))
    ]
    audio_only = [
        f
        for f in formats
        if _codec_present(f.get("acodec")) and not _codec_present(f.get("vcodec"))
    ]
    combined = [
        f
        for f in formats
        if _codec_present(f.get("vcodec")) and _codec_present(f.get("acodec"))
    ]

    best_video = max(video_only, key=_quality_tuple, default=None)
    best_audio = max(audio_only, key=_audio_quality_tuple, default=None)
    best_combined = max(combined, key=_quality_tuple, default=None)

    if best_video is not None and best_audio is not None:
        split_height = best_video.get("height") or 0
        combined_height = (best_combined.get("height") or 0) if best_combined else 0
        if best_combined is None or split_height >= combined_height:
            _log(
                "Format selected: video=%s audio=%s (split, highest quality)"
                % (best_video.get("format_id"), best_audio.get("format_id"))
            )
            return [str(best_video["format_id"]), str(best_audio["format_id"])], True

    if best_combined is not None:
        _log("Format selected: combined=%s" % best_combined.get("format_id"))
        return [str(best_combined["format_id"])], False

    if best_video is not None:
        _log("Format selected: video-only=%s" % best_video.get("format_id"))
        return [str(best_video["format_id"])], False

    if best_audio is not None:
        _log("Format selected: audio-only=%s" % best_audio.get("format_id"))
        return [str(best_audio["format_id"])], False

    if formats:
        return [str(formats[-1]["format_id"])], False

    return ["best"], False


def _unwrap_info(info: dict) -> dict:
    if not info:
        raise EngineError("UNAVAILABLE", "Content unavailable or unsupported.", "Empty extractor result.")
    if info.get("_type") == "playlist":
        entries = [e for e in (info.get("entries") or []) if e]
        if not entries:
            raise EngineError("UNAVAILABLE", "Content unavailable or empty playlist.", "Empty playlist.")
        for entry in entries:
            formats = entry.get("formats") or []
            has_video = any(_codec_present(f.get("vcodec")) for f in formats if isinstance(f, dict))
            if has_video or entry.get("vcodec") not in (None, "none"):
                return entry
        return entries[0]
    return info


def _map_exception(exc: BaseException) -> EngineError:
    if isinstance(exc, DownloadCancelled):
        return EngineError("CANCELLED", "Download was cancelled.", str(exc))
    if isinstance(exc, EngineError):
        return exc

    text = "%s: %s" % (exc.__class__.__name__, exc)
    lowered = text.lower()
    detail = traceback.format_exc()

    if any(
        token in lowered
        for token in (
            "private",
            "login required",
            "only available for registered",
            "join to see",
            "not available",
            "unavailable",
            "this content isn't available",
        )
    ):
        return EngineError(
            "PRIVATE",
            "The content may be private or unavailable.",
            detail or text,
        )
    if any(token in lowered for token in ("403", "429", "http error 4", "rejected", "rate-limit", "rate limit")):
        return EngineError("REJECTED", "The media server rejected the request.", detail or text)
    if any(
        token in lowered
        for token in (
            "network",
            "timed out",
            "timeout",
            "temporarily unavailable",
            "connection",
            "name or service not known",
            "nodename nor servname",
            "failed to resolve",
            "ssl",
        )
    ):
        return EngineError("NETWORK", "Network connection failed.", detail or text)
    if any(token in lowered for token in ("unsupported url", "no video formats", "there is no video", "no suitable extractor")):
        return EngineError("NO_MEDIA", "Content unavailable or unsupported website.", detail or text)
    return EngineError("PROCESS", "The downloader could not process this media.", detail or text)


def _base_opts(temp_dir: str) -> dict:
    return {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "overwrites": True,
        "retries": 5,
        "fragment_retries": 5,
        "socket_timeout": 30,
        "outtmpl": os.path.join(temp_dir, "%(id)s.%(ext)s"),
        "noprogress": True,
        "ignoreconfig": True,
        "restrictfilenames": True,
        "compat_opts": set(),
        # Prefer native fragment joining so yt-dlp does not need a CLI ffmpeg.
        "hls_use_mpegts": False,
        "allow_unplayable_formats": False,
    }


def fetch_metadata(url: str) -> dict:
    _log("Validating URL")
    _log("Starting yt-dlp (metadata)")
    try:
        opts = _base_opts(os.environ.get("HOME", "."))
        opts["skip_download"] = True
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = _unwrap_info(ydl.extract_info(url, download=False))
        title = info.get("title") or info.get("id") or "media"
        return json.dumps(
            {
                "id": info.get("id"),
                "title": str(title),
                "ext": info.get("ext"),
                "duration": info.get("duration"),
                "ok": True,
            }
        )
    except DownloadCancelled as exc:
        mapped = _map_exception(exc)
        return json.dumps({"ok": False, "code": mapped.code, "message": mapped.message, "detail": mapped.detail})
    except Exception as exc:
        mapped = _map_exception(exc)
        _log("Metadata error: %s" % mapped.code)
        return json.dumps({"ok": False, "code": mapped.code, "message": mapped.message, "detail": mapped.detail})


def download(url: str, temp_dir: str, progress, cancel_checker) -> dict:
    os.makedirs(temp_dir, exist_ok=True)
    _log("Validating URL")
    _log("Starting yt-dlp")

    def emit(status: str, percent=None, downloaded=None, total=None, message=None):
        _raise_if_cancelled(cancel_checker)
        if progress is None:
            return
        try:
            progress.on_progress(
                status,
                None if percent is None else float(percent),
                None if downloaded is None else int(downloaded),
                None if total is None else int(total),
                message,
            )
        except DownloadCancelled:
            raise
        except Exception as exc:
            _log("Progress callback failed: %s" % exc)

    def hook(d: dict) -> None:
        _raise_if_cancelled(cancel_checker)
        status = d.get("status")
        if status == "downloading":
            downloaded = _safe_int(d.get("downloaded_bytes"))
            total = _safe_int(d.get("total_bytes") or d.get("total_bytes_estimate"))
            percent = None
            if downloaded is not None and total:
                percent = max(0.0, min(100.0, downloaded * 100.0 / total))
            else:
                percent_str = d.get("_percent_str")
                if isinstance(percent_str, str):
                    try:
                        percent = float(percent_str.strip().strip("%"))
                    except ValueError:
                        percent = None
            emit("downloading", percent, downloaded, total, "Downloading")
            if percent is not None:
                _log("Progress: %s%%" % int(percent))
        elif status == "finished":
            emit("downloading", 100.0, _safe_int(d.get("downloaded_bytes")), _safe_int(d.get("total_bytes")), "Download started")

    try:
        emit("fetching", None, None, None, "Fetching information")
        info_opts = _base_opts(temp_dir)
        info_opts["skip_download"] = True
        with yt_dlp.YoutubeDL(info_opts) as ydl:
            info = _unwrap_info(ydl.extract_info(url, download=False))

        format_ids, needs_merge = _pick_formats(info)
        downloaded_files: list[str] = []

        for index, format_id in enumerate(format_ids):
            _raise_if_cancelled(cancel_checker)
            _log("Download started format=%s" % format_id)
            emit("downloading", None, None, None, "Downloading")
            prefix = "v" if index == 0 else "a"
            opts = _base_opts(temp_dir)
            opts.update(
                {
                    "format": format_id,
                    "outtmpl": os.path.join(temp_dir, prefix + ".%(ext)s"),
                    "progress_hooks": [hook],
                    "postprocessors": [],
                    "keepvideo": True,
                }
            )
            with yt_dlp.YoutubeDL(opts) as ydl:
                result = ydl.extract_info(url, download=True)
                result = _unwrap_info(result) if result else {}
                requested = result.get("requested_downloads") or []
                if requested:
                    for item in requested:
                        filepath = item.get("filepath") or item.get("filename")
                        if filepath and os.path.isfile(filepath):
                            downloaded_files.append(filepath)
                filename = ydl.prepare_filename(result) if result else None
                if filename and os.path.isfile(filename) and filename not in downloaded_files:
                    downloaded_files.append(filename)

        existing = [path for path in downloaded_files if os.path.isfile(path)]
        if not existing:
            # Fallback: any media written into the temp directory.
            for name in sorted(os.listdir(temp_dir)):
                path = os.path.join(temp_dir, name)
                if os.path.isfile(path) and not name.endswith(".part"):
                    existing.append(path)

        if not existing:
            raise EngineError("NO_MEDIA", "This post could not be downloaded.", "No files were written.")

        _log("yt-dlp finished files=%s merge=%s" % (existing, needs_merge))
        return json.dumps(
            {
                "ok": True,
                "files": existing,
                "needs_merge": bool(needs_merge and len(existing) > 1),
                "title": str(info.get("title") or info.get("id") or "media"),
                "id": info.get("id"),
                "ext": os.path.splitext(existing[0])[1].lstrip("."),
            }
        )
    except DownloadCancelled as exc:
        mapped = _map_exception(exc)
        _log("Cancelled")
        return json.dumps({"ok": False, "code": mapped.code, "message": mapped.message, "detail": mapped.detail})
    except Exception as exc:
        mapped = _map_exception(exc)
        _log("Error %s" % mapped.code)
        return json.dumps(
            {
                "ok": False,
                "code": mapped.code,
                "message": mapped.message,
                "detail": mapped.detail,
            }
        )
