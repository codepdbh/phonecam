import 'dart:io';
import 'package:shared_models/shared_models.dart';
import 'network_interface_analyzer.dart';

class ManualConnectionService {
  /// Test if a target host and port is reachable
  static Future<bool> testReachability(String ipAddress, int port,
      {Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final socket = await Socket.connect(ipAddress, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Create a DeviceInfo for manual connection
  static DeviceInfo createManualDevice({
    required String ipAddress,
    int port = 41236,
    String? name,
  }) {
    final transport = NetworkInterfaceAnalyzer.isUsbSubnet(ipAddress)
        ? TransportType.usbTethering
        : TransportType.manualIp;

    return DeviceInfo(
      id: 'manual_${ipAddress.replaceAll('.', '_')}_$port',
      name: name ?? 'Manual Device ($ipAddress)',
      model: 'Manual IP',
      osVersion: '',
      platform: DevicePlatform.android,
      ipAddress: ipAddress,
      port: port,
      transportType: transport,
      lastSeen: DateTime.now(),
    );
  }
}
