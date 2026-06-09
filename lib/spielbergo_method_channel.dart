import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'spielbergo_platform_interface.dart';

/// An implementation of [SpielbergoPlatform] that uses method channels.
class MethodChannelSpielbergo extends SpielbergoPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('spielbergo');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<String?> pickVideo({required List<String> recordTimes}) async {
    final path = await methodChannel.invokeMethod<String>('pickVideo', {
      'recordTimes': recordTimes,
    });
    return path;
  }
}
