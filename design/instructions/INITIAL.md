# Spielbergo Video Editor

This is based on the TikTok vertical video editor.

See attached PDF for screens.

Icon files are located in `assets/icons/`

## Instantiating in Flutter

Flutter apps should use this widget in the following pattern:

```dart
File? videoFile = await SpielbergoVideoEditor().pickVideo(
  recordTimes: ["10s", "30s", "1m", "10m"],
);
```

## PDF Screen Reference

### Screen 1.1, Initial State

Full screen with black background.

9:16 camera view.

Close button in top left - discards all temp recorded video files, exits the screen and returns a `null` video file. Gate this with a modal dialog to confirm exit.

Camera options in top right, stacked:

* Switch Camera (flips between front and back camera - defaults to front)
* Flash / No Flash (enables phone light when using back camera and turns a portion of the screen white for front camera to provide reflective light)

---

Record options: passed in as an array from flutter (e.g. `recordTimes: ["10s", "30s", "1m", "10m"]`)

Selecting one of these sets the max recording time for the video. Default value should be first in array.

---

Record button in bottom centre starts recording video.

### Screen 1.2, Recording State

When recording, there is a red stop button in the centre of the circle.

Disable and hide camera option buttons and close button.

A small red arc will show how much of the allowed recording time has been used.

Pressing stop stops recording and saves the clip to temporary storage.

Starting recording again creates a new clip.

Once the max record time is reached, the video automatically stops and saves the final clip.

There is a countdown next to the record button which displays how long is left of the allowed record time.

### Screen 1.3, Clips Recorded State

When a video is not recording, show a red circle in the white circle to indicate that it is ready to record again.

Show and enable the camera option buttons.

Show a small delete arrow next to the record button - this shows a modal dialog asking if the user wants to delete the last recorded clip. There should be options to Delete or Cancel.

Show a circle checkmark button next to the delete button. This moves onto screen 2.

### Screen 2.1, Basic Editor Clip

This should play the recorded clips on a loop in the order that they were recorded.

Show a back arrow on the top left which goes back to the recording screen.

Show a next button at the bottom of the screen which creates a single video file from the recorded clips and returns it to the Flutter instance as a result of `pickVideo`. It should also delete temp video files once the main video file has been created.

## Returned Video File

This should be rendered vertically as 9:16 ratio and stored in temporary storage so the user can use the flutter file object to move it or upload it as needed.

## Compatibility

Please produce versions of this editor that work for both iOS and Android.

Place relevant code in the `ios/` and `android/` directories.