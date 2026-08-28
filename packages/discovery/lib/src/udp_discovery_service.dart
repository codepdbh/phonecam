import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_models/shared_models.dart';
import 'discovery_beacon.dart';
import 'network_interface_analyzer.dart';

class UdpDiscoveryService {
  static const int discoveryPort = 41235;
  static const Duration beaconInterval = Duration(milliseconds: 1500);
  static const Duration deviceTimeout = Duration(seconds: 6);

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _pruneTimer;

  final Map<String, DeviceInfo> _discoveredDevices = {};
  final _deviceStreamController =
      StreamController<List<DeviceInfo>>.broadcast();

  Stream<List<DeviceInfo>> get devicesStream =>
      _deviceStreamController.stream;

  List<DeviceInfo> get devices => _discoveredDevices.values.toList();

  bool _isBroadcasting = false;
  bool _isListening = false;

  bool get isBroadcasting => _isBroadcasting;
  bool get isListening => _isListening;

  /// Start listening for broadcast discovery beacons
  Future<void> startListening() async {
    if (_isListening) return;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: false,
      );

      _socket?.broadcastEnabled = true;
      _socket?.readEventsEnabled = true;
      _isListening = true;

      _socket?.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram != null) {
            _handleIncomingPacket(datagram);
          }
        }
      });

      _pruneTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _pruneStaleDevices();
      });
    } catch (e) {
      debugPrint('[DISCOVERY] Failed to bind UDP listening socket: $e');
    }
  }

  /// Broadcast local device identity to the LAN
  Future<void> startBroadcasting(DeviceInfo localDevice) async {
    if (_isBroadcasting) return;

    if (_socket == null) {
      try {
        _socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0,
          reuseAddress: true,
        );
        _socket?.broadcastEnabled = true;
      } catch (e) {
        debugPrint('[DISCOVERY] Failed to bind UDP sender socket: $e');
        return;
      }
    }

    _isBroadcasting = true;

    _broadcastTimer = Timer.periodic(beaconInterval, (_) async {
      await _sendBroadcastBeacon(localDevice);
    });

    // Send first beacon immediately
    await _sendBroadcastBeacon(localDevice);
  }

  Future<void> _sendBroadcastBeacon(DeviceInfo device) async {
    if (_socket == null) return;

    try {
      final activeInterfaces =
          await NetworkInterfaceAnalyzer.getActiveInterfaces();
      final beacon = DiscoveryBeacon(
        type: 'announce',
        device: device,
      );
      final bytes = beacon.toBytes();

      // 1. Send to standard subnet broadcast 255.255.255.255
      _socket?.send(
        bytes,
        InternetAddress('255.255.255.255'),
        discoveryPort,
      );

      // 2. Also send directly to subnet broadcasts for all active interfaces
      for (final iface in activeInterfaces) {
        final ipParts = iface.ipAddress.split('.');
        if (ipParts.length == 4) {
          final subnetBroadcast = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}.255';
          _socket?.send(
            bytes,
            InternetAddress(subnetBroadcast),
            discoveryPort,
          );
        }
      }
    } catch (e) {
      debugPrint('[DISCOVERY] Broadcast error: $e');
    }
  }

  void _handleIncomingPacket(Datagram datagram) {
    final senderIp = datagram.address.address;
    final beacon = DiscoveryBeacon.fromBytes(datagram.data, senderIp);
    if (beacon == null) return;

    // Detect transport type for sender IP
    final transport = NetworkInterfaceAnalyzer.isUsbSubnet(senderIp)
        ? TransportType.usbTethering
        : TransportType.wifi;

    final updatedDevice = beacon.device.copyWith(
      ipAddress: senderIp,
      transportType: transport,
      lastSeen: DateTime.now(),
    );

    _discoveredDevices[updatedDevice.id] = updatedDevice;
    _deviceStreamController.add(devices);
  }

  void _pruneStaleDevices() {
    final now = DateTime.now();
    var changed = false;

    _discoveredDevices.removeWhere((id, device) {
      if (now.difference(device.lastSeen) > deviceTimeout) {
        changed = true;
        return true;
      }
      return false;
    });

    if (changed) {
      _deviceStreamController.add(devices);
    }
  }

  /// Stop discovery & clean up sockets
  void stop() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _socket?.close();
    _socket = null;
    _isBroadcasting = false;
    _isListening = false;
  }

  void dispose() {
    stop();
    _deviceStreamController.close();
  }
}
