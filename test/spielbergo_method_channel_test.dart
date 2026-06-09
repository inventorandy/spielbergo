import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spielbergo/spielbergo_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelSpielbergo platform = MethodChannelSpielbergo();
  const MethodChannel channel = MethodChannel('spielbergo');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'pickVideo') {
            expect(methodCall.arguments, {
              'recordTimes': ['15s', '30s'],
            });
            return '/tmp/spielbergo.mp4';
          }
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('pickVideo', () async {
    expect(
      await platform.pickVideo(recordTimes: ['15s', '30s']),
      '/tmp/spielbergo.mp4',
    );
  });
}
