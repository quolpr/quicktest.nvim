import 'package:flutter_test/flutter_test.dart';
import 'package:qd/qd.dart';
import 'package:qd/qd_platform_interface.dart';
import 'package:qd/qd_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockQdPlatform
    with MockPlatformInterfaceMixin
    implements QdPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final QdPlatform initialPlatform = QdPlatform.instance;

  test('$MethodChannelQd is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelQd>());
  });

  test('getPlatformVersion', () async {
    Qd qdPlugin = Qd();
    MockQdPlatform fakePlatform = MockQdPlatform();
    QdPlatform.instance = fakePlatform;

    expect(await qdPlugin.getPlatformVersion(), '42');
  });
}
