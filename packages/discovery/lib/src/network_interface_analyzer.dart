import 'dart:io';
import 'package:shared_models/shared_models.dart';

class NetworkInterfaceInfo {
  final String name;
  final String ipAddress;
  final TransportType transportType;

  const NetworkInterfaceInfo({
    required this.name,
    required this.ipAddress,
    required this.transportType,
  });

  @override
  String toString() => '$name ($ipAddress, ${transportType.name})';
}

class NetworkInterfaceAnalyzer {
  static const List<String> _usbSubnetPrefixes = [
    '192.168.42.', // Android standard USB tethering
    '192.168.44.', // Alternate Android USB tethering
    '172.20.10.',  // iOS USB hotspot
    '192.168.137.', // Windows ICS
  ];

  static const List<String> _usbInterfaceKeywords = [
    'rndis',
    'ncm',
    'usb',
    'tether',
    'remote ndis',
    'cdc',
    'apple mobile',
  ];

  /// Detect transport type given an interface name and IP address
  static TransportType detectTransportType({
    required String interfaceName,
    required String ipAddress,
  }) {
    final lowerName = interfaceName.toLowerCase();
    for (final kw in _usbInterfaceKeywords) {
      if (lowerName.contains(kw)) {
        return TransportType.usbTethering;
      }
    }

    for (final prefix in _usbSubnetPrefixes) {
      if (ipAddress.startsWith(prefix)) {
        return TransportType.usbTethering;
      }
    }

    return TransportType.wifi;
  }

  /// Get all active local IPv4 network interfaces
  static Future<List<NetworkInterfaceInfo>> getActiveInterfaces() async {
    final results = <NetworkInterfaceInfo>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback || addr.address.startsWith('169.254.')) continue;

          final transport = detectTransportType(
            interfaceName: iface.name,
            ipAddress: addr.address,
          );

          results.add(
            NetworkInterfaceInfo(
              name: iface.name,
              ipAddress: addr.address,
              transportType: transport,
            ),
          );
        }
      }
    } catch (_) {
      // Fallback empty list on permission or platform issue
    }
    return results;
  }

  /// Check if an IP address belongs to a USB tethering subnet
  static bool isUsbSubnet(String ipAddress) {
    for (final prefix in _usbSubnetPrefixes) {
      if (ipAddress.startsWith(prefix)) return true;
    }
    return false;
  }
}
