import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'qd_platform_interface.dart';

/// An implementation of [QdPlatform] that uses method channels.
class MethodChannelQd extends QdPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('qd');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
