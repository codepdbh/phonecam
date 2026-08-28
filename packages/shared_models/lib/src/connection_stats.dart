import 'package:meta/meta.dart';
import 'device_info.dart';
import 'video_format.dart';

@immutable
class ConnectionStats {
  final int width;
  final int height;
  final double fps;
  final double bitrateKbps;
  final int latencyMs;
  final int lostFrames;
  final double packetLossPercentage;
  final double jitterMs;
  final VideoCodec codec;
  final TransportType transportType;
  final DateTime timestamp;

  const ConnectionStats({
    this.width = 1920,
    this.height = 1080,
    this.fps = 30.0,
    this.bitrateKbps = 6500.0,
    this.latencyMs = 28,
    this.lostFrames = 0,
    this.packetLossPercentage = 0.0,
    this.jitterMs = 2.5,
    this.codec = VideoCodec.h264,
    this.transportType = TransportType.wifi,
    required this.timestamp,
  });

  String get resolutionLabel => '${width}x$height';

  String get formattedBitrate {
    if (bitrateKbps >= 1000) {
      return '${(bitrateKbps / 1000).toStringAsFixed(1)} Mbps';
    }
    return '${bitrateKbps.toStringAsFixed(0)} Kbps';
  }

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'fps': fps,
        'bitrateKbps': bitrateKbps,
        'latencyMs': latencyMs,
        'lostFrames': lostFrames,
        'packetLossPercentage': packetLossPercentage,
        'jitterMs': jitterMs,
        'codec': codec.name,
        'transportType': transportType.name,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ConnectionStats.fromJson(Map<String, dynamic> json) {
    return ConnectionStats(
      width: (json['width'] as num?)?.toInt() ?? 1920,
      height: (json['height'] as num?)?.toInt() ?? 1080,
      fps: (json['fps'] as num?)?.toDouble() ?? 30.0,
      bitrateKbps: (json['bitrateKbps'] as num?)?.toDouble() ?? 6000.0,
      latencyMs: (json['latencyMs'] as num?)?.toInt() ?? 0,
      lostFrames: (json['lostFrames'] as num?)?.toInt() ?? 0,
      packetLossPercentage:
          (json['packetLossPercentage'] as num?)?.toDouble() ?? 0.0,
      jitterMs: (json['jitterMs'] as num?)?.toDouble() ?? 0.0,
      codec: VideoCodec.fromString(json['codec'] as String? ?? 'h264'),
      transportType:
          TransportType.fromString(json['transportType'] as String? ?? 'wifi'),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  ConnectionStats copyWith({
    int? width,
    int? height,
    double? fps,
    double? bitrateKbps,
    int? latencyMs,
    int? lostFrames,
    double? packetLossPercentage,
    double? jitterMs,
    VideoCodec? codec,
    TransportType? transportType,
    DateTime? timestamp,
  }) {
    return ConnectionStats(
      width: width ?? this.width,
      height: height ?? this.height,
      fps: fps ?? this.fps,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      latencyMs: latencyMs ?? this.latencyMs,
      lostFrames: lostFrames ?? this.lostFrames,
      packetLossPercentage: packetLossPercentage ?? this.packetLossPercentage,
      jitterMs: jitterMs ?? this.jitterMs,
      codec: codec ?? this.codec,
      transportType: transportType ?? this.transportType,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
