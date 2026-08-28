import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import '../../providers/mobile_provider.dart';

class FloatingControls extends ConsumerWidget {
  const FloatingControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mobileProvider);
    final notifier = ref.read(mobileProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Zoom Slider Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0F141E).withOpacity(0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF222C3E)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.zoom_in_rounded,
                      size: 16, color: Color(0xFF00E5FF)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 140,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6),
                        activeTrackColor: const Color(0xFF00E5FF),
                        inactiveTrackColor: const Color(0xFF233047),
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        value: state.currentZoom,
                        min: 1.0,
                        max: 8.0,
                        onChanged: (val) => notifier.setZoom(val),
                      ),
                    ),
                  ),
                  Text(
                    '${state.currentZoom.toStringAsFixed(1)}x',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Main Action Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F141E).withOpacity(0.9),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFF263248), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Switch Camera
                  IconButton(
                    tooltip: 'Flip Camera',
                    icon: const Icon(
                      Icons.flip_camera_android_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: notifier.switchCamera,
                  ),
                  const SizedBox(width: 12),

                  // Torch
                  IconButton(
                    tooltip: 'Flash',
                    icon: Icon(
                      state.isTorchOn
                          ? Icons.flashlight_on_rounded
                          : Icons.flashlight_off_rounded,
                      color: state.isTorchOn
                          ? const Color(0xFFFFD600)
                          : Colors.white70,
                      size: 24,
                    ),
                    onPressed: notifier.toggleTorch,
                  ),
                  const SizedBox(width: 12),

                  // Resolution & FPS Settings Sheet
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(
                      Icons.tune_rounded,
                      color: Color(0xFF00E5FF),
                      size: 24,
                    ),
                    onPressed: () => _showSettingsSheet(context, ref),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131A26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final state = ref.watch(mobileProvider);
        final notifier = ref.read(mobileProvider.notifier);

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C394F),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Stream Quality & Format',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'RESOLUTION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8B949E),
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: VideoResolution.all.map((res) {
                  final isSelected =
                      state.selectedResolution.width == res.width &&
                          state.selectedResolution.height == res.height;
                  return ChoiceChip(
                    label: Text(res.label),
                    selected: isSelected,
                    selectedColor: const Color(0xFF00E5FF),
                    backgroundColor: const Color(0xFF1B2332),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? const Color(0xFF0F141E)
                          : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        notifier.setResolution(res);
                        Navigator.pop(ctx);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'TARGET FRAMERATE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8B949E),
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [30, 60].map((fps) {
                  final isSelected = state.selectedFps == fps;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('$fps FPS'),
                      selected: isSelected,
                      selectedColor: const Color(0xFF00E5FF),
                      backgroundColor: const Color(0xFF1B2332),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? const Color(0xFF0F141E)
                            : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          notifier.setFps(fps);
                          Navigator.pop(ctx);
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}
