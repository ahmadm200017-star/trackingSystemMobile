# MDF Tracker — Flutter app

Mobile half of the MDF object-tracking system. It renders the camera feed, seeds
an OpenCV tracker from a tap, draws the bounding box, and streams the tracked
coordinates to `backend/MdfTracker.Api` so the dashboard can replay them.

Implements [`../FlutterApplication.md`](../FlutterApplication.md) against the
schema in [`../Backend.md`](../Backend.md).

## Running

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5201
```

`10.0.2.2` is the default and is how the **Android emulator** reaches the host
machine, matching `launchSettings.json`. On a physical device pass your machine's
LAN address, e.g. `--dart-define=API_BASE_URL=http://192.168.1.10:5201`. The
WebSocket base is derived from it (`http` → `ws`) unless you also pass
`--dart-define=WS_BASE_URL=...`.

```bash
flutter analyze   # clean
flutter test      # 19 unit tests
```

## Layout

```
lib/src/
  core/config/app_config.dart          endpoints, --dart-define overrides
  core/network/api_exception.dart
  features/settings/                   domain / data / application / presentation
  features/tracking/
    domain/      enums, DTOs, FrameGeometry (coordinate transforms)
    data/        frame conversion, tracker engines, REST client, WebSocket
    application/ TrackingController + TrackingState
    presentation/TrackingScreen, HUD, CustomPainter overlay
```

State management is Riverpod (`NotifierProvider`), no code generation.

## How a session runs

1. `TrackingScreen` opens the camera from settings and starts `startImageStream`.
2. A tap is projected from viewport pixels into camera-image pixels, becomes a
   96 px (on-screen) square seed box, and sets status to `initializing`.
   That is also when `POST /api/sessions` fires and the WebSocket opens — a
   session in the database therefore always corresponds to real tracking.
3. Each frame: luminance plane → `cv.Mat` → downscale → `tracker.update()`.
   A hit pushes a frame message over the socket and repaints the box; a miss
   flips the HUD to **Lost Object** and emits a `lost` event (a later hit emits
   `reacquired`, which is what paints the dashboard's red zones).
4. **Stop** posts the summary: `endTime`, `averageFps`, and `isSuccessful`
   (true when the run was stopped with the target still locked).

Design decisions worth knowing:

- **Drop-first frame loop.** A frame arriving while the previous one is still in
  the tracker is discarded, not queued. Latency stays bounded and the FPS number
  measures frames the tracker actually processed.
- **Grayscale only.** OpenCV's trackers work on one channel, so the YUV
  luminance plane is used directly and the YUV→BGR conversion is skipped
  entirely. On iOS the BGRA buffer is converted once per frame.
- **Async OpenCV.** `initAsync` / `updateAsync` / `resizeAsync` run on OpenCV's
  native thread pool, so the Dart isolate keeps rendering at 60 fps while the
  tracker crunches frames.
- **Lossy socket.** Pending frames sit in a bounded queue (600, ~20 s at 30 fps)
  with drop-oldest and exponential-backoff reconnect. Dropped frames are counted
  and shown in the HUD rather than hidden.
- **One coordinate transform.** `FrameGeometry` / `FrameProjection` own the
  sensor-rotation, front-camera mirroring and `BoxFit.cover` maths for both taps
  and boxes. Unit-tested for round-trip identity.

## Known gap: CSRT and KCF have no Dart binding

`FlutterApplication.md` calls for `cv.TrackerCSRT.create()` / `cv.TrackerKCF.create()`.
**Those constructors do not exist in the Flutter OpenCV bindings.** `opencv_core`
1.4.5 (and `opencv_dart`, same `dartcv4` 1.1.8 core) binds exactly one tracker:
`cv::TrackerMIL`. CSRT and KCF are present in the native OpenCV `video` module
but are not exposed through FFI.

Rather than silently substituting one algorithm for another — which would
mislabel `tracker_algorithm` and poison the dashboard's CSRT-vs-KCF success
chart — the app:

- keeps all three algorithms in `TrackerAlgorithm`,
- lists them in Settings, with unavailable ones disabled and labelled
  *"no binding"* plus the reason,
- defaults to MIL, the one that genuinely runs.

To add CSRT/KCF later, the only change needed is a branch in
`OpenCvTrackerFactory.create` (`lib/src/features/tracking/data/object_tracker.dart`)
plus the matching entry in `TrackerAvailability.available`. That requires either
a `dartcv4` release that binds them, or a small platform channel to the native
OpenCV SDK.

## Backend work this app expects

The API currently has models and a `DbContext` but no endpoints. The app calls:

| Method | Path | Body |
| --- | --- | --- |
| `POST` | `/api/sessions` | `cameraType`, `trackerAlgorithm`, `startTime`, `screenWidth`, `screenHeight` → `{ id, sessionNumber }` |
| `POST` | `/api/sessions/{id}/complete` | `endTime`, `averageFps`, `isSuccessful` |
| `POST` | `/api/sessions/{id}/events` | `eventType` (`lost` \| `reacquired`), `occurredAt` |
| `POST` | `/api/sessions/{id}/frames` | `{ frames: [...] }` — REST fallback, unused while the socket is up |
| `WS` | `/ws/tracking?sessionId={id}` | `{ "type": "frame" \| "event", "sessionId": ..., "payload": {...} }` |

Two schema notes:

- `TrackerAlgorithm` in `Models/Enums.cs` needs a `Mil` member for the algorithm
  the app can actually run today.
- `SessionFrame` already carries `Width`/`Height`; the frame payload sends them.

## Platform configuration

- **Android**: `CAMERA` + `INTERNET` permissions, `minSdk` raised to 24
  (required by the OpenCV native libraries), `usesCleartextTraffic` enabled so
  plain-HTTP LAN development works. Remove that flag before shipping.
- **iOS**: `NSCameraUsageDescription`, and `NSAllowsLocalNetworking` for the same
  development reason.
- The UI is locked to portrait — the preview transform assumes it.
