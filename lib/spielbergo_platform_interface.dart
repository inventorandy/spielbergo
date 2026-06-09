import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'spielbergo_method_channel.dart';

abstract class SpielbergoPlatform extends PlatformInterface {
  /// Constructs a SpielbergoPlatform.
  SpielbergoPlatform() : super(token: _token);

  static final Object _token = Object();

  static SpielbergoPlatform _instance = MethodChannelSpielbergo();

  /// The default instance of [SpielbergoPlatform] to use.
  ///
  /// Defaults to [MethodChannelSpielbergo].
  static SpielbergoPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SpielbergoPlatform] when
  /// they register themselves.
  static set instance(SpielbergoPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<String?> pickVideo({required List<String> recordTimes}) {
    throw UnimplementedError('pickVideo() has not been implemented.');
  }
}
