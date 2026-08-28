import 'package:meta/meta.dart';

enum TransportType {
  wifi,
  usbTethering,
  manualIp;

  String get label {
    switch (this) {
      case TransportType.wifi:
        return 'Wi-Fi';
      case TransportType.usbTethering:
        return 'USB';
      case TransportType.manualIp:
        return 'Manual IP';
    }
  }

  static TransportType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'usb':
      case 'usbtethering':
        return TransportType.usbTethering;
      case 'manual':
      case 'manualip':
        return TransportType.manualIp;
      case 'wifi':
      default:
        return TransportType.wifi;
    }
  }
}

enum DevicePlatform {
  android,
  windows,
  unknown;

  static DevicePlatform fromString(String value) {
    switch (value.toLowerCase()) {
      case 'android':
        return DevicePlatform.android;
      case 'windows':
        return DevicePlatform.windows;
      default:
        return DevicePlatform.unknown;
    }
  }
}

@immutable
class DeviceInfo {
  final String id;
  final String name;
  final String model;
  final String osVersion;
  final DevicePlatform platform;
  final String ipAddress;
  final int port;
  final TransportType transportType;
  final DateTime lastSeen;

  const DeviceInfo({
    required this.id,
    required this.name,
    required this.model,
    required this.osVersion,
    required this.platform,
    required this.ipAddress,
    required this.port,
    this.transportType = TransportType.wifi,
    required this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'model': model,
        'osVersion': osVersion,
        'platform': platform.name,
        'ipAddress': ipAddress,
        'port': port,
        'transportType': transportType.name,
        'lastSeen': lastSeen.toIso8601String(),
      };

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Device',
      model: json['model'] as String? ?? '',
      osVersion: json['osVersion'] as String? ?? '',
      platform: DevicePlatform.fromString(json['platform'] as String? ?? ''),
      ipAddress: json['ipAddress'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 41236,
      transportType: TransportType.fromString(json['transportType'] as String? ?? 'wifi'),
      lastSeen: json['lastSeen'] != null
          ? DateTime.tryParse(json['lastSeen'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  DeviceInfo copyWith({
    String? id,
    String? name,
    String? model,
    String? osVersion,
    DevicePlatform? platform,
    String? ipAddress,
    int? port,
    TransportType? transportType,
    DateTime? lastSeen,
  }) {
    return DeviceInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      model: model ?? this.model,
      osVersion: osVersion ?? this.osVersion,
      platform: platform ?? this.platform,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      transportType: transportType ?? this.transportType,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          ipAddress == other.ipAddress;

  @override
  int get hashCode => id.hashCode ^ ipAddress.hashCode;

  @override
  String toString() =>
      'DeviceInfo(id: $id, name: $name, ip: $ipAddress:$port, transport: ${transportType.name})';
}
