import 'package:flutter_test/flutter_test.dart';
import 'package:discovery/discovery.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  group('Discovery Tests', () {
    test('NetworkInterfaceAnalyzer USB vs Wi-Fi detection', () {
      final usbTransport1 = NetworkInterfaceAnalyzer.detectTransportType(
        interfaceName: 'rndis0',
        ipAddress: '192.168.42.129',
      );
      expect(usbTransport1, TransportType.usbTethering);

      final usbTransport2 = NetworkInterfaceAnalyzer.detectTransportType(
        interfaceName: 'Ethernet 2',
        ipAddress: '192.168.42.5',
      );
      expect(usbTransport2, TransportType.usbTethering);

      final wifiTransport = NetworkInterfaceAnalyzer.detectTransportType(
        interfaceName: 'Wi-Fi',
        ipAddress: '192.168.1.150',
      );
      expect(wifiTransport, TransportType.wifi);
    });

    test('DiscoveryBeacon serialization and deserialization', () {
      final dev = DeviceInfo(
        id: 'phone_01',
        name: 'Galaxy S24',
        model: 'SM-S928B',
        osVersion: 'Android 14',
        platform: DevicePlatform.android,
        ipAddress: '192.168.1.45',
        port: 41236,
        lastSeen: DateTime.now(),
      );

      final beacon = DiscoveryBeacon(type: 'announce', device: dev);
      final bytes = beacon.toBytes();
      final parsed = DiscoveryBeacon.fromBytes(bytes, '192.168.1.45');

      expect(parsed, isNotNull);
      expect(parsed!.device.id, 'phone_01');
      expect(parsed.device.name, 'Galaxy S24');
      expect(parsed.device.ipAddress, '192.168.1.45');
    });

    test('ManualConnectionService device creation', () {
      final dev = ManualConnectionService.createManualDevice(
        ipAddress: '192.168.1.100',
        port: 41236,
        name: 'Office Phone',
      );

      expect(dev.ipAddress, '192.168.1.100');
      expect(dev.port, 41236);
      expect(dev.name, 'Office Phone');
      expect(dev.transportType, TransportType.manualIp);
    });
  });
}
