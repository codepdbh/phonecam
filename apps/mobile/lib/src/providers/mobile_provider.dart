import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:discovery/discovery.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_models/shared_models.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/camera_capture_service.dart';
import '../services/pairing_manager.dart';
import '../services/signaling_server.dart';
import '../services/webrtc_sender_service.dart';

class MobileState {
  final DeviceInfo localDevice;
  final AppConnectionState connectionState;
  final ConnectionStats? stats;
  final bool hasCameraPermission;
  final bool isCameraReady;
  final bool isStreaming;
  final bool isTorchOn;
  final double currentZoom;
  final VideoResolution selectedResolution;
  final int selectedFps;
  final String? pendingPin;
  final String? clientHostName;

  const MobileState({
    required this.localDevice,
    this.connectionState = AppConnectionState.idle,
    this.stats,
    this.hasCameraPermission = false,
    this.isCameraReady = false,
    this.isStreaming = false,
    this.isTorchOn = false,
    this.currentZoom = 1.0,
    this.selectedResolution = VideoResolution.r1080p,
    this.selectedFps = 30,
    this.pendingPin,
    this.clientHostName,
  });

  MobileState copyWith({
    DeviceInfo? localDevice,
    AppConnectionState? connectionState,
    ConnectionStats? stats,
    bool? hasCameraPermission,
    bool? isCameraReady,
    bool? isStreaming,
    bool? isTorchOn,
    double? currentZoom,
    VideoResolution? selectedResolution,
    int? selectedFps,
    String? pendingPin,
    String? clientHostName,
  }) {
    return MobileState(
      localDevice: localDevice ?? this.localDevice,
      connectionState: connectionState ?? this.connectionState,
      stats: stats ?? this.stats,
      hasCameraPermission: hasCameraPermission ?? this.hasCameraPermission,
      isCameraReady: isCameraReady ?? this.isCameraReady,
      isStreaming: isStreaming ?? this.isStreaming,
      isTorchOn: isTorchOn ?? this.isTorchOn,
      currentZoom: currentZoom ?? this.currentZoom,
      selectedResolution: selectedResolution ?? this.selectedResolution,
      selectedFps: selectedFps ?? this.selectedFps,
      pendingPin: pendingPin ?? this.pendingPin,
      clientHostName: clientHostName ?? this.clientHostName,
    );
  }
}

class MobileNotifier extends StateNotifier<MobileState> {
  final CameraCaptureService cameraService = CameraCaptureService();
  final SignalingServer signalingServer = SignalingServer();
  final UdpDiscoveryService discoveryService = UdpDiscoveryService();
  WebRtcSenderService? senderService;

  StreamSubscription? _connSub;
  StreamSubscription? _statsSub;
  StreamSubscription? _clientSub;

  MobileNotifier()
      : super(
          MobileState(
            localDevice: DeviceInfo(
              id: 'android_dev',
              name: 'Android Device',
              model: 'PhoneCam',
              osVersion: 'Android',
              platform: DevicePlatform.android,
              ipAddress: '0.0.0.0',
              port: 41236,
              lastSeen: DateTime.now(),
            ),
          ),
        ) {
    _init();
  }

  Future<void> _init() async {
    // 1. Keep screen on
    try {
      await WakelockPlus.enable();
    } catch (_) {}

    // 2. Request permissions
    final status = await Permission.camera.request();
    final hasPerm = status.isGranted;
    state = state.copyWith(hasCameraPermission: hasPerm);

    if (!hasPerm) return;

    // 3. Resolve Device Details
    String devName = 'Android Device';
    String model = 'PhoneCam';
    String osVer = 'Android';
    try {
      final devInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await devInfo.androidInfo;
        devName = '${android.brand} ${android.model}';
        model = android.model;
        osVer = 'Android ${android.version.release}';
      }
    } catch (_) {}

    final interfaces = await NetworkInterfaceAnalyzer.getActiveInterfaces();
    final primaryIp = interfaces.isNotEmpty ? interfaces.first.ipAddress : '0.0.0.0';
    final transport = interfaces.isNotEmpty ? interfaces.first.transportType : TransportType.wifi;

    final localDev = DeviceInfo(
      id: 'phonecam_${primaryIp.replaceAll('.', '_')}',
      name: devName,
      model: model,
      osVersion: osVer,
      platform: DevicePlatform.android,
      ipAddress: primaryIp,
      port: 41236,
      transportType: transport,
      lastSeen: DateTime.now(),
    );

    state = state.copyWith(localDevice: localDev);

    // 4. Start Camera Stream
    final cameraStarted = await cameraService.startStream(
      resolution: state.selectedResolution,
      fps: state.selectedFps,
    );

    state = state.copyWith(isCameraReady: cameraStarted);

    // 5. Start Signaling Server
    await signalingServer.start();

    // 6. Setup WebRtcSenderService
    senderService = WebRtcSenderService(
      cameraService: cameraService,
      signalingServer: signalingServer,
      deviceName: devName,
    );

    _connSub = senderService!.onConnectionStateChanged.listen((connState) {
      state = state.copyWith(
        connectionState: connState,
        isStreaming: connState == AppConnectionState.streaming,
      );
    });

    _statsSub = senderService!.onStatsUpdated.listen((stats) {
      state = state.copyWith(stats: stats);
    });

    _clientSub = signalingServer.onClientConnected.listen((hasClient) {
      if (!hasClient && state.connectionState == AppConnectionState.streaming) {
        state = state.copyWith(
          connectionState: AppConnectionState.idle,
          isStreaming: false,
        );
      }
    });

    // 7. Start UDP LAN Discovery Broadcast
    await discoveryService.startBroadcasting(localDev);
  }

  Future<void> switchCamera() async {
    await cameraService.switchCamera();
    state = state.copyWith(
      isTorchOn: cameraService.isTorchOn,
      currentZoom: cameraService.currentZoom,
      isCameraReady: cameraService.isStreamActive,
    );
  }

  Future<void> setZoom(double zoom) async {
    await cameraService.setZoom(zoom);
    state = state.copyWith(currentZoom: zoom);
  }

  Future<void> toggleTorch() async {
    await cameraService.toggleTorch();
    state = state.copyWith(isTorchOn: cameraService.isTorchOn);
  }

  Future<void> setResolution(VideoResolution res) async {
    await cameraService.startStream(resolution: res);
    state = state.copyWith(
      selectedResolution: res,
      isCameraReady: cameraService.isStreamActive,
    );
  }

  Future<void> setFps(int fps) async {
    await cameraService.startStream(fps: fps);
    state = state.copyWith(
      selectedFps: fps,
      isCameraReady: cameraService.isStreamActive,
    );
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _statsSub?.cancel();
    _clientSub?.cancel();
    discoveryService.dispose();
    senderService?.dispose();
    signalingServer.dispose();
    cameraService.dispose();
    WakelockPlus.disable();
    super.dispose();
  }
}

final mobileProvider =
    StateNotifierProvider<MobileNotifier, MobileState>((ref) {
  return MobileNotifier();
});
