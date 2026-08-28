import 'dart:async';
import 'package:discovery/discovery.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import '../services/webrtc_receiver_service.dart';

class PhoneCamState {
  final List<DeviceInfo> discoveredDevices;
  final DeviceInfo? connectedDevice;
  final AppConnectionState connectionState;
  final ConnectionStats? stats;
  final DeviceCapabilities? capabilities;
  final bool isVirtualCameraActive;
  final bool isVideoStreamReady;
  final double currentZoom;
  final bool isTorchOn;
  final VideoResolution selectedResolution;
  final int selectedFps;
  final String? activeCameraId;

  const PhoneCamState({
    this.discoveredDevices = const [],
    this.connectedDevice,
    this.connectionState = AppConnectionState.idle,
    this.stats,
    this.capabilities,
    this.isVirtualCameraActive = false,
    this.isVideoStreamReady = false,
    this.currentZoom = 1.0,
    this.isTorchOn = false,
    this.selectedResolution = VideoResolution.r1080p,
    this.selectedFps = 30,
    this.activeCameraId,
  });

  PhoneCamState copyWith({
    List<DeviceInfo>? discoveredDevices,
    DeviceInfo? connectedDevice,
    AppConnectionState? connectionState,
    ConnectionStats? stats,
    DeviceCapabilities? capabilities,
    bool? isVirtualCameraActive,
    bool? isVideoStreamReady,
    double? currentZoom,
    bool? isTorchOn,
    VideoResolution? selectedResolution,
    int? selectedFps,
    String? activeCameraId,
  }) {
    return PhoneCamState(
      discoveredDevices: discoveredDevices ?? this.discoveredDevices,
      connectedDevice: connectedDevice ?? this.connectedDevice,
      connectionState: connectionState ?? this.connectionState,
      stats: stats ?? this.stats,
      capabilities: capabilities ?? this.capabilities,
      isVirtualCameraActive:
          isVirtualCameraActive ?? this.isVirtualCameraActive,
      isVideoStreamReady: isVideoStreamReady ?? this.isVideoStreamReady,
      currentZoom: currentZoom ?? this.currentZoom,
      isTorchOn: isTorchOn ?? this.isTorchOn,
      selectedResolution: selectedResolution ?? this.selectedResolution,
      selectedFps: selectedFps ?? this.selectedFps,
      activeCameraId: activeCameraId ?? this.activeCameraId,
    );
  }
}

class PhoneCamNotifier extends StateNotifier<PhoneCamState> {
  final UdpDiscoveryService _discoveryService = UdpDiscoveryService();
  final AdbUsbDiscoveryService _adbUsbDiscoveryService = AdbUsbDiscoveryService();
  final WebRtcReceiverService receiverService = WebRtcReceiverService();

  StreamSubscription? _udpSub;
  StreamSubscription? _usbSub;
  StreamSubscription? _connSub;
  StreamSubscription? _statsSub;
  StreamSubscription? _capsSub;
  StreamSubscription? _streamSub;

  final Map<String, DeviceInfo> _mergedDevices = {};

  PhoneCamNotifier() : super(const PhoneCamState()) {
    _init();
  }

  void _init() {
    _discoveryService.startListening();
    _adbUsbDiscoveryService.startPolling();

    _udpSub = _discoveryService.devicesStream.listen((udpDevs) {
      _updateDeviceList(udp: udpDevs);
    });

    _usbSub = _adbUsbDiscoveryService.devicesStream.listen((usbDevs) {
      _updateDeviceList(usb: usbDevs);
    });

    _connSub = receiverService.onConnectionStateChanged.listen((connState) {
      state = state.copyWith(
        connectionState: connState,
        isVideoStreamReady: connState == AppConnectionState.streaming &&
            receiverService.hasVideoStream,
      );
    });

    _streamSub = receiverService.onVideoStreamReady.listen((ready) {
      state = state.copyWith(isVideoStreamReady: ready);
    });

    _statsSub = receiverService.onStatsUpdated.listen((stats) {
      state = state.copyWith(stats: stats);
    });

    _capsSub = receiverService.onCapabilitiesReceived.listen((caps) {
      state = state.copyWith(
        capabilities: caps,
        activeCameraId: caps.cameras.isNotEmpty ? caps.cameras.first.id : null,
      );
    });
  }

  void _updateDeviceList({List<DeviceInfo>? udp, List<DeviceInfo>? usb}) {
    if (udp != null) {
      _mergedDevices.removeWhere((_, d) => d.transportType == TransportType.wifi);
      for (final d in udp) {
        _mergedDevices[d.id] = d;
      }
    }

    if (usb != null) {
      _mergedDevices.removeWhere((_, d) => d.transportType == TransportType.usbTethering);
      for (final d in usb) {
        _mergedDevices[d.id] = d;
      }
    }

    state = state.copyWith(discoveredDevices: _mergedDevices.values.toList());
  }

  Future<void> connect(DeviceInfo device) async {
    state = state.copyWith(connectedDevice: device, isVideoStreamReady: false);
    await receiverService.connect(device);
  }

  void disconnect() {
    receiverService.disconnect();
    state = state.copyWith(
      connectedDevice: null,
      connectionState: AppConnectionState.idle,
      isVideoStreamReady: false,
      stats: null,
    );
  }

  void toggleVirtualCamera() {
    final newState = !state.isVirtualCameraActive;
    final success = receiverService.toggleVirtualCamera(newState);
    state = state.copyWith(isVirtualCameraActive: success);
  }

  void switchCamera() {
    receiverService.switchCamera();
  }

  void selectCamera(String id) {
    receiverService.selectCamera(id);
    state = state.copyWith(activeCameraId: id);
  }

  void setZoom(double zoom) {
    receiverService.setZoom(zoom);
    state = state.copyWith(currentZoom: zoom);
  }

  void toggleTorch() {
    final next = !state.isTorchOn;
    receiverService.setTorch(next);
    state = state.copyWith(isTorchOn: next);
  }

  void setResolution(VideoResolution res) {
    receiverService.setResolution(res);
    state = state.copyWith(selectedResolution: res);
  }

  void setFps(int fps) {
    receiverService.setFps(fps);
    state = state.copyWith(selectedFps: fps);
  }

  @override
  void dispose() {
    _udpSub?.cancel();
    _usbSub?.cancel();
    _connSub?.cancel();
    _statsSub?.cancel();
    _capsSub?.cancel();
    _streamSub?.cancel();
    _discoveryService.dispose();
    _adbUsbDiscoveryService.dispose();
    receiverService.dispose();
    super.dispose();
  }
}

final phoneCamProvider =
    StateNotifierProvider<PhoneCamNotifier, PhoneCamState>((ref) {
  return PhoneCamNotifier();
});
