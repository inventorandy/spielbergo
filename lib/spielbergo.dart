import 'dart:io';

import 'spielbergo_platform_interface.dart';

class Spielbergo {
  Future<String?> getPlatformVersion() {
    return SpielbergoPlatform.instance.getPlatformVersion();
  }
}

class SpielbergoVideoEditor {
  Future<File?> pickVideo({required List<String> recordTimes}) async {
    final path = await SpielbergoPlatform.instance.pickVideo(
      recordTimes: recordTimes,
    );

    return path == null ? null : File(path);
  }
}
