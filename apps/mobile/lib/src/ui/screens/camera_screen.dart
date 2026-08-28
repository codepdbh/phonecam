import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../providers/mobile_provider.dart';
import '../widgets/floating_controls.dart';
import '../widgets/status_pill.dart';

class CameraScreen extends ConsumerWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mobileProvider);
    final notifier = ref.read(mobileProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Viewfinder Canvas
          Positioned.fill(
            child: (state.hasCameraPermission && state.isCameraReady)
                ? RTCVideoView(
                    notifier.cameraService.localRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    mirror: notifier.cameraService.currentCamera?.facing.name ==
                        'front',
                  )
                : state.hasCameraPermission
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation(Color(0xFF00E5FF)),
                        ),
                      )
                    : _buildPermissionDeniedView(context),
          ),

          // 2. Top HUD Pill
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(child: StatusPill()),
          ),

          // 3. Bottom Controls
          if (state.hasCameraPermission)
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(child: FloatingControls()),
            ),
        ],
      ),
    );
  }

  Widget _buildPermissionDeniedView(BuildContext context) {
    return Container(
      color: const Color(0xFF090D13),
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFF5252).withOpacity(0.3),
                ),
              ),
              child: const Icon(
                Icons.no_photography_rounded,
                size: 48,
                color: Color(0xFFFF5252),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Camera Permission Required',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'PhoneCam requires access to your camera to stream high-definition video to your Windows PC.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: const Color(0xFF090D13),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.settings_rounded),
              label: const Text(
                'Open App Settings',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => openAppSettings(),
            ),
          ],
        ),
      ),
    );
  }
}
