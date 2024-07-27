import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'qd_method_channel.dart';

abstract class QdPlatform extends PlatformInterface {
  /// Constructs a QdPlatform.
  QdPlatform() : super(token: _token);

  static final Object _token = Object();

  static QdPlatform _instance = MethodChannelQd();

  /// The default instance of [QdPlatform] to use.
  ///
  /// Defaults to [MethodChannelQd].
  static QdPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [QdPlatform] when
  /// they register themselves.
  static set instance(QdPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
