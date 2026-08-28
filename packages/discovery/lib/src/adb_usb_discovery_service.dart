import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_models/shared_models.dart';

class AdbUsbDiscoveryService {
  Timer? _pollTimer;
  final _deviceStreamController =
      StreamController<List<DeviceInfo>>.broadcast();

  Stream<List<DeviceInfo>> get devicesStream =>
      _deviceStreamController.stream;

  final Map<String, DeviceInfo> _usbDevices = {};
  List<DeviceInfo> get devices => _usbDevices.values.toList();

  bool _isRunning = false;

  void startPolling({Duration interval = const Duration(seconds: 3)}) {
    if (_isRunning) return;
    _isRunning = true;
    _pollAdbDevices();
    _pollTimer = Timer.periodic(interval, (_) => _pollAdbDevices());
  }

  Future<void> _pollAdbDevices() async {
    if (!_isRunning || !Platform.isWindows) return;

    try {
      final adbExe = _findAdbExecutable();
      if (adbExe == null) return;

      final result = await Process.run(adbExe, ['devices', '-l']);
      if (!_isRunning || result.exitCode != 0) return;

      final output = result.stdout as String;
      final lines = output.split('\n');
      final currentSeenIds = <String>{};

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('List of devices')) continue;

        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length >= 2 && parts[1] == 'device') {
          final serial = parts[0];
          currentSeenIds.add(serial);

          var model = 'Android Phone';
          for (final p in parts) {
            if (p.startsWith('model:')) {
              model = p.substring(6).replaceAll('_', ' ');
            }
          }

          // Forward port 41236 for zero-config USB streaming
          try {
            await Process.run(adbExe, ['-s', serial, 'forward', 'tcp:41236', 'tcp:41236']);
          } catch (_) {}

          final dev = DeviceInfo(
            id: 'usb_$serial',
            name: '$model (USB)',
            model: model,
            osVersion: 'Android (USB Cable)',
            platform: DevicePlatform.android,
            ipAddress: '127.0.0.1',
            port: 41236,
            transportType: TransportType.usbTethering,
            lastSeen: DateTime.now(),
          );

          _usbDevices[dev.id] = dev;
        }
      }

      _usbDevices.removeWhere((id, _) {
        final serial = id.replaceFirst('usb_', '');
        return !currentSeenIds.contains(serial);
      });

      if (!_deviceStreamController.isClosed) {
        _deviceStreamController.add(devices);
      }
    } catch (e) {
      debugPrint('[ADB_USB] Discovery polling error: $e');
    }
  }

  String? _findAdbExecutable() {
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    final possible = [
      '$localAppData\\Android\\Sdk\\platform-tools\\adb.exe',
      'adb.exe',
      'adb',
    ];

    for (final p in possible) {
      if (File(p).existsSync()) return p;
    }
    return 'adb';
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _isRunning = false;
  }

  void dispose() {
    stop();
    _deviceStreamController.close();
  }
}
