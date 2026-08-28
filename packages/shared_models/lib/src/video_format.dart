import 'package:meta/meta.dart';

enum VideoCodec {
  h264,
  vp8,
  vp9;

  String get mimeType {
    switch (this) {
      case VideoCodec.h264:
        return 'video/H264';
      case VideoCodec.vp8:
        return 'video/VP8';
      case VideoCodec.vp9:
        return 'video/VP9';
    }
  }

  static VideoCodec fromString(String value) {
    switch (value.toLowerCase()) {
      case 'vp8':
        return VideoCodec.vp8;
      case 'vp9':
        return VideoCodec.vp9;
      case 'h264':
      default:
        return VideoCodec.h264;
    }
  }
}

@immutable
class VideoResolution {
  final int width;
  final int height;
  final String label;

  const VideoResolution({
    required this.width,
    required this.height,
    required this.label,
  });

  static const VideoResolution r720p =
      VideoResolution(width: 1280, height: 720, label: '720p HD');
  static const VideoResolution r1080p =
      VideoResolution(width: 1920, height: 1080, label: '1080p Full HD');
  static const VideoResolution r1440p =
      VideoResolution(width: 2560, height: 1440, label: '1440p 2K QHD');
  static const VideoResolution r4k =
      VideoResolution(width: 3840, height: 2160, label: '4K Ultra HD');

  static const List<VideoResolution> all = [
    r720p,
    r1080p,
    r1440p,
    r4k,
  ];

  double get aspectRatio => width / (height > 0 ? height : 1);
  int get totalPixels => width * height;

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'label': label,
      };

  factory VideoResolution.fromJson(Map<String, dynamic> json) {
    return VideoResolution(
      width: (json['width'] as num?)?.toInt() ?? 1920,
      height: (json['height'] as num?)?.toInt() ?? 1080,
      label: json['label'] as String? ?? 'Custom',
    );
  }

  static VideoResolution fromDimensions(int width, int height) {
    for (final res in all) {
      if (res.width == width && res.height == height) return res;
    }
    return VideoResolution(
      width: width,
      height: height,
      label: '${width}x$height',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoResolution &&
          runtimeType == other.runtimeType &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => width.hashCode ^ height.hashCode;

  @override
  String toString() => '$label (${width}x$height)';
}

@immutable
class VideoFormat {
  final VideoResolution resolution;
  final int fps;
  final VideoCodec codec;
  final int bitrateKbps;

  const VideoFormat({
    this.resolution = VideoResolution.r1080p,
    this.fps = 30,
    this.codec = VideoCodec.h264,
    this.bitrateKbps = 6000,
  });

  Map<String, dynamic> toJson() => {
        'resolution': resolution.toJson(),
        'fps': fps,
        'codec': codec.name,
        'bitrateKbps': bitrateKbps,
      };

  factory VideoFormat.fromJson(Map<String, dynamic> json) {
    return VideoFormat(
      resolution: json['resolution'] != null
          ? VideoResolution.fromJson(json['resolution'] as Map<String, dynamic>)
          : VideoResolution.r1080p,
      fps: (json['fps'] as num?)?.toInt() ?? 30,
      codec: VideoCodec.fromString(json['codec'] as String? ?? 'h264'),
      bitrateKbps: (json['bitrateKbps'] as num?)?.toInt() ?? 6000,
    );
  }

  VideoFormat copyWith({
    VideoResolution? resolution,
    int? fps,
    VideoCodec? codec,
    int? bitrateKbps,
  }) {
    return VideoFormat(
      resolution: resolution ?? this.resolution,
      fps: fps ?? this.fps,
      codec: codec ?? this.codec,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoFormat &&
          runtimeType == other.runtimeType &&
          resolution == other.resolution &&
          fps == other.fps &&
          codec == other.codec &&
          bitrateKbps == other.bitrateKbps;

  @override
  int get hashCode =>
      resolution.hashCode ^ fps.hashCode ^ codec.hashCode ^ bitrateKbps.hashCode;

  @override
  String toString() =>
      'VideoFormat(${resolution.label}, $fps FPS, ${codec.name.toUpperCase()}, ${bitrateKbps}kbps)';
}
