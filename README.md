# SlapMac

A Flutter macOS app that plays a **user-provided slap sound** when a chassis impact/slap is detected.

No keyboard or trackpad interaction is required.

## Detection pipeline

Native Swift `SlapDetector` combines five concurrent signal checks over accelerometer data:

- High-pass filter (removes gravity trend)
- STA/LTA ratio at 3 timescales
- CUSUM change detection
- Kurtosis spike detection
- Peak/MAD outlier detection

When enough algorithms vote positive, the app emits a slap event and plays your selected sound.

## Features

- No predefined sounds: user picks their own audio file (`mp3`, `wav`, `m4a`, `aac`, `ogg`, `flac`).
- Native macOS accelerometer monitoring (`CoreMotion`) bridged to Flutter via channels.
- Live slap counter and last event.
- Volume slider and preview playback.

## Run

```bash
flutter pub get
flutter run -d macos
```
