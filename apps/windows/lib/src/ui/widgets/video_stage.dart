import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_models/shared_models.dart';
import '../../providers/connection_provider.dart';

class VideoStage extends ConsumerWidget {
  const VideoStage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(phoneCamProvider);
    final notifier = ref.read(phoneCamProvider.notifier);
    final isStreaming = state.isVideoStreamReady &&
        notifier.receiverService.renderer.srcObject != null;

    return Container(
      color: const Color(0xFF090D13),
      child: Stack(
        children: [
          // 1. Video Canvas
          Center(
            child: isStreaming
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: RTCVideoView(
                        notifier.receiverService.renderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                      ),
                    ),
                  )
                : _buildIdleStage(context, state),
          ),

          // 2. Top Right Camera Control Bar
          if (isStreaming)
            Positioned(
              top: 20,
              right: 20,
              child: _buildControlsBar(context, state, notifier),
            ),

          // 3. Center Bottom: Big Virtual Camera Toggle Button
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: _buildVirtualCameraControl(state, notifier),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleStage(BuildContext context, PhoneCamState state) {
    final isConnecting =
        state.connectionState == AppConnectionState.connecting ||
            state.connectionState == AppConnectionState.streaming;

    return Container(
      width: 720,
      height: 405,
      decoration: BoxDecoration(
        color: const Color(0xFF101622),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1F283B), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF182032),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF283450)),
            ),
            child: isConnecting
                ? const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF00E5FF)),
                    ),
                  )
                : const Icon(
                    Icons.camera_alt_outlined,
                    size: 48,
                    color: Color(0xFF00E5FF),
                  ),
          ),
          const SizedBox(height: 20),
          Text(
            state.connectedDevice == null
                ? 'No Device Connected'
                : 'Connecting to ${state.connectedDevice!.name}...',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            state.connectedDevice == null
                ? 'Select an available phone from the left panel to begin streaming.'
                : 'Negotiating low-latency video stream...',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsBar(
      BuildContext context, PhoneCamState state, PhoneCamNotifier notifier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF121824).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF243048)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Switch Camera button
          IconButton(
            tooltip: 'Switch Camera',
            icon: const Icon(Icons.flip_camera_android_rounded,
                color: Colors.white),
            onPressed: notifier.switchCamera,
          ),
          const SizedBox(width: 8),

          // Torch Toggle
          IconButton(
            tooltip: state.isTorchOn ? 'Turn Flash Off' : 'Turn Flash On',
            icon: Icon(
              state.isTorchOn
                  ? Icons.flashlight_on_rounded
                  : Icons.flashlight_off_rounded,
              color: state.isTorchOn ? const Color(0xFFFFD600) : Colors.white70,
            ),
            onPressed: notifier.toggleTorch,
          ),
          const SizedBox(width: 8),

          // Resolution Dropdown
          DropdownButton<VideoResolution>(
            value: state.selectedResolution,
            dropdownColor: const Color(0xFF151C2B),
            underline: const SizedBox(),
            icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF00E5FF)),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            items: VideoResolution.all.map((res) {
              return DropdownMenuItem<VideoResolution>(
                value: res,
                child: Text(res.label),
              );
            }).toList(),
            onChanged: (res) {
              if (res != null) notifier.setResolution(res);
            },
          ),
          const SizedBox(width: 8),

          // FPS Switcher
          InkWell(
            onTap: () {
              final nextFps = state.selectedFps == 30 ? 60 : 30;
              notifier.setFps(nextFps);
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1D263B),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF2F3D5D)),
              ),
              child: Text(
                '${state.selectedFps} FPS',
                style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVirtualCameraControl(
      PhoneCamState state, PhoneCamNotifier notifier) {
    final isActive = state.isVirtualCameraActive;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          if (isActive)
            BoxShadow(
              color: const Color(0xFF00E676).withValues(alpha: 0.35),
              blurRadius: 20,
              spreadRadius: 2,
            ),
        ],
      ),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isActive ? const Color(0xFF00E676) : const Color(0xFF1C2538),
          foregroundColor: isActive ? const Color(0xFF07140E) : Colors.white,
          elevation: 4,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: BorderSide(
              color:
                  isActive ? const Color(0xFF00E676) : const Color(0xFF334264),
              width: 1.5,
            ),
          ),
        ),
        icon: Icon(
          isActive ? Icons.videocam_rounded : Icons.videocam_off_rounded,
          size: 22,
        ),
        label: Text(
          isActive
              ? 'PhoneCam Virtual Camera Active'
              : 'Activate Virtual Camera',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
            color: isActive ? const Color(0xFF07140E) : Colors.white,
          ),
        ),
        onPressed: notifier.toggleVirtualCamera,
      ),
    );
  }
}
