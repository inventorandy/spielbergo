# spielbergo

Spielbergo is a Flutter plugin that presents a native, vertical video editor on
iOS and Android.

## Usage

```dart
final videoFile = await SpielbergoVideoEditor().pickVideo(
  recordTimes: ['10m', '1m', '30s', '15s'],
  defaultRecordTime: '1m',
);
```

`pickVideo` opens a full-screen native editor. It returns a temporary video file
when the user taps `Next`, or `null` when the user cancels.

## Native Permissions

Android apps must allow camera and microphone access. The plugin manifest
declares these permissions so they are merged into consuming apps.

iOS apps must include usage descriptions in their app `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app records video clips.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app records audio with video clips.</string>
```

## Current Editor

The native editor supports:

* front-camera recording by default
* camera switching
* back-camera torch and front-camera screen light
* configurable max record durations
* multiple recorded clips
* delete-last-clip confirmation
* looping preview
* final merged temp video export
