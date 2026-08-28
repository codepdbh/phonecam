import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  group('Shared Models Tests', () {
    test('DeviceInfo serialization & deserialization', () {
      final dev = DeviceInfo(
        id: 'dev_123',
        name: 'Pixel 9 Pro',
        model: 'Pixel 9',
        osVersion: 'Android 15',
        platform: DevicePlatform.android,
        ipAddress: '192.168.1.45',
        port: 41236,
        transportType: TransportType.wifi,
        lastSeen: DateTime(2026, 8, 28, 12, 0),
      );

      final json = dev.toJson();
      final fromJson = DeviceInfo.fromJson(json);

      expect(fromJson.id, 'dev_123');
      expect(fromJson.name, 'Pixel 9 Pro');
      expect(fromJson.transportType, TransportType.wifi);
      expect(fromJson.ipAddress, '192.168.1.45');
    });

    test('VideoResolution and VideoFormat', () {
      const format = VideoFormat(
        resolution: VideoResolution.r1080p,
        fps: 60,
        codec: VideoCodec.h264,
        bitrateKbps: 8000,
      );

      final json = format.toJson();
      final fromJson = VideoFormat.fromJson(json);

      expect(fromJson.resolution.width, 1920);
      expect(fromJson.resolution.height, 1080);
      expect(fromJson.fps, 60);
      expect(fromJson.codec, VideoCodec.h264);
    });

    test('CameraInfo & Capabilities serialization', () {
      const camera = CameraInfo(
        id: 'back_main',
        name: 'Main Wide',
        facing: CameraFacing.backMain,
        zoomMin: 1.0,
        zoomMax: 8.0,
        hasTorch: true,
      );

      const caps = CameraCapabilities(
        cameras: [camera],
        defaultCameraId: 'back_main',
      );

      final json = caps.toJson();
      final fromJson = CameraCapabilities.fromJson(json);

      expect(fromJson.cameras.length, 1);
      expect(fromJson.cameras.first.facing, CameraFacing.backMain);
      expect(fromJson.cameras.first.hasTorch, true);
    });

    test('ConnectionStats formatting', () {
      final stats = ConnectionStats(
        width: 1920,
        height: 1080,
        fps: 30.0,
        bitrateKbps: 6500.0,
        latencyMs: 25,
        lostFrames: 0,
        timestamp: DateTime.now(),
      );

      expect(stats.formattedBitrate, '6.5 Mbps');
      expect(stats.resolutionLabel, '1920x1080');
    });
  });
}
