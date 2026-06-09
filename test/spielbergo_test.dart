import 'package:flutter_test/flutter_test.dart';
import 'package:spielbergo/spielbergo.dart';
import 'package:spielbergo/spielbergo_platform_interface.dart';
import 'package:spielbergo/spielbergo_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockSpielbergoPlatform
    with MockPlatformInterfaceMixin
    implements SpielbergoPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<String?> pickVideo({required List<String> recordTimes}) =>
      Future.value('/tmp/spielbergo.mp4');
}

void main() {
  final SpielbergoPlatform initialPlatform = SpielbergoPlatform.instance;

  test('$MethodChannelSpielbergo is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSpielbergo>());
  });

  test('getPlatformVersion', () async {
    Spielbergo spielbergoPlugin = Spielbergo();
    MockSpielbergoPlatform fakePlatform = MockSpielbergoPlatform();
    SpielbergoPlatform.instance = fakePlatform;

    expect(await spielbergoPlugin.getPlatformVersion(), '42');
  });

  test('pickVideo', () async {
    SpielbergoVideoEditor editor = SpielbergoVideoEditor();
    MockSpielbergoPlatform fakePlatform = MockSpielbergoPlatform();
    SpielbergoPlatform.instance = fakePlatform;

    final file = await editor.pickVideo(recordTimes: ['15s']);

    expect(file?.path, '/tmp/spielbergo.mp4');
  });
}
