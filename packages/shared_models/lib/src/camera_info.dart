import 'package:meta/meta.dart';
import 'video_format.dart';

enum CameraFacing {
  front,
  backMain,
  ultraWide,
  telephoto,
  unknown;

  String get label {
    switch (this) {
      case CameraFacing.front:
        return 'Front Camera';
      case CameraFacing.backMain:
        return 'Main Camera (1x)';
      case CameraFacing.ultraWide:
        return 'Ultra-Wide Camera (0.6x)';
      case CameraFacing.telephoto:
        return 'Telephoto Camera (3x/5x)';
      case CameraFacing.unknown:
        return 'Camera';
    }
  }

  static CameraFacing fromString(String value) {
    switch (value.toLowerCase()) {
      case 'front':
        return CameraFacing.front;
      case 'ultrawide':
      case 'ultra_wide':
      case 'wide':
        return CameraFacing.ultraWide;
      case 'telephoto':
      case 'tele':
        return CameraFacing.telephoto;
      case 'back':
      case 'backmain':
      case 'back_main':
      case 'main':
        return CameraFacing.backMain;
      default:
        return CameraFacing.unknown;
    }
  }
}

@immutable
class CameraInfo {
  final String id;
  final String name;
  final CameraFacing facing;
  final double zoomMin;
  final double zoomMax;
  final double currentZoom;
  final bool hasTorch;
  final bool isTorchOn;
  final List<VideoResolution> supportedResolutions;
  final List<int> supportedFps;
  final double minExposureOffset;
  final double maxExposureOffset;

  const CameraInfo({
    required this.id,
    required this.name,
    required this.facing,
    this.zoomMin = 1.0,
    this.zoomMax = 10.0,
    this.currentZoom = 1.0,
    this.hasTorch = false,
    this.isTorchOn = false,
    this.supportedResolutions = const [
      VideoResolution.r720p,
      VideoResolution.r1080p,
    ],
    this.supportedFps = const [30, 60],
    this.minExposureOffset = -2.0,
    this.maxExposureOffset = 2.0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'facing': facing.name,
        'zoomMin': zoomMin,
        'zoomMax': zoomMax,
        'currentZoom': currentZoom,
        'hasTorch': hasTorch,
        'isTorchOn': isTorchOn,
        'supportedResolutions':
            supportedResolutions.map((r) => r.toJson()).toList(),
        'supportedFps': supportedFps,
        'minExposureOffset': minExposureOffset,
        'maxExposureOffset': maxExposureOffset,
      };

  factory CameraInfo.fromJson(Map<String, dynamic> json) {
    final resList = (json['supportedResolutions'] as List<dynamic>?)
            ?.map((e) => VideoResolution.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [VideoResolution.r720p, VideoResolution.r1080p];

    final fpsList = (json['supportedFps'] as List<dynamic>?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        const [30, 60];

    return CameraInfo(
      id: json['id'] as String? ?? '0',
      name: json['name'] as String? ?? 'Default Camera',
      facing: CameraFacing.fromString(json['facing'] as String? ?? 'backMain'),
      zoomMin: (json['zoomMin'] as num?)?.toDouble() ?? 1.0,
      zoomMax: (json['zoomMax'] as num?)?.toDouble() ?? 10.0,
      currentZoom: (json['currentZoom'] as num?)?.toDouble() ?? 1.0,
      hasTorch: json['hasTorch'] as bool? ?? false,
      isTorchOn: json['isTorchOn'] as bool? ?? false,
      supportedResolutions: resList,
      supportedFps: fpsList,
      minExposureOffset: (json['minExposureOffset'] as num?)?.toDouble() ?? -2.0,
      maxExposureOffset: (json['maxExposureOffset'] as num?)?.toDouble() ?? 2.0,
    );
  }

  CameraInfo copyWith({
    String? id,
    String? name,
    CameraFacing? facing,
    double? zoomMin,
    double? zoomMax,
    double? currentZoom,
    bool? hasTorch,
    bool? isTorchOn,
    List<VideoResolution>? supportedResolutions,
    List<int>? supportedFps,
    double? minExposureOffset,
    double? maxExposureOffset,
  }) {
    return CameraInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      facing: facing ?? this.facing,
      zoomMin: zoomMin ?? this.zoomMin,
      zoomMax: zoomMax ?? this.zoomMax,
      currentZoom: currentZoom ?? this.currentZoom,
      hasTorch: hasTorch ?? this.hasTorch,
      isTorchOn: isTorchOn ?? this.isTorchOn,
      supportedResolutions: supportedResolutions ?? this.supportedResolutions,
      supportedFps: supportedFps ?? this.supportedFps,
      minExposureOffset: minExposureOffset ?? this.minExposureOffset,
      maxExposureOffset: maxExposureOffset ?? this.maxExposureOffset,
    );
  }
}

@immutable
class CameraCapabilities {
  final List<CameraInfo> cameras;
  final String defaultCameraId;

  const CameraCapabilities({
    required this.cameras,
    required this.defaultCameraId,
  });

  CameraInfo? get defaultCamera {
    for (final c in cameras) {
      if (c.id == defaultCameraId) return c;
    }
    return cameras.isNotEmpty ? cameras.first : null;
  }

  CameraInfo? getCamera(String id) {
    for (final c in cameras) {
      if (c.id == id) return c;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'cameras': cameras.map((c) => c.toJson()).toList(),
        'defaultCameraId': defaultCameraId,
      };

  factory CameraCapabilities.fromJson(Map<String, dynamic> json) {
    final list = (json['cameras'] as List<dynamic>?)
            ?.map((e) => CameraInfo.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    return CameraCapabilities(
      cameras: list,
      defaultCameraId: json['defaultCameraId'] as String? ??
          (list.isNotEmpty ? list.first.id : '0'),
    );
  }
}

@immutable
class DeviceCapabilities {
  final String deviceName;
  final String platform;
  final List<CameraInfo> cameras;
  final List<VideoCodec> supportedCodecs;
  final VideoResolution maxResolution;
  final int maxFps;

  const DeviceCapabilities({
    required this.deviceName,
    required this.platform,
    required this.cameras,
    this.supportedCodecs = const [VideoCodec.h264, VideoCodec.vp8],
    this.maxResolution = VideoResolution.r1080p,
    this.maxFps = 60,
  });

  Map<String, dynamic> toJson() => {
        'deviceName': deviceName,
        'platform': platform,
        'cameras': cameras.map((c) => c.toJson()).toList(),
        'supportedCodecs': supportedCodecs.map((c) => c.name).toList(),
        'maxResolution': maxResolution.toJson(),
        'maxFps': maxFps,
      };

  factory DeviceCapabilities.fromJson(Map<String, dynamic> json) {
    final cams = (json['cameras'] as List<dynamic>?)
            ?.map((e) => CameraInfo.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    final codecs = (json['supportedCodecs'] as List<dynamic>?)
            ?.map((e) => VideoCodec.fromString(e as String))
            .toList() ??
        const [VideoCodec.h264, VideoCodec.vp8];

    return DeviceCapabilities(
      deviceName: json['deviceName'] as String? ?? 'Device',
      platform: json['platform'] as String? ?? 'Android',
      cameras: cams,
      supportedCodecs: codecs,
      maxResolution: json['maxResolution'] != null
          ? VideoResolution.fromJson(json['maxResolution'] as Map<String, dynamic>)
          : VideoResolution.r1080p,
      maxFps: (json['maxFps'] as num?)?.toInt() ?? 60,
    );
  }
}
