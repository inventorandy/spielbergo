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
  Future<String?> pickVideo({
    required List<String> recordTimes,
    String? defaultRecordTime,
  }) async {
    final arguments = <String, Object?>{
      'recordTimes': recordTimes,
      'defaultRecordTime': ?defaultRecordTime,
    };
    final path = await methodChannel.invokeMethod<String>(
      'pickVideo',
      arguments,
    );
    return path;
  }
}
