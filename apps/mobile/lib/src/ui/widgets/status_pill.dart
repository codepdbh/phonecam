import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import '../../providers/mobile_provider.dart';

class StatusPill extends ConsumerWidget {
  const StatusPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mobileProvider);
    final stats = state.stats;
    final isConnected = state.connectionState == AppConnectionState.streaming;
    final isUsb = state.localDevice.transportType == TransportType.usbTethering;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F141E).withOpacity(0.9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isConnected
                  ? const Color(0xFF00E5FF).withOpacity(0.5)
                  : const Color(0xFF222C3E),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status indicator dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isConnected
                        ? const Color(0xFF00E676)
                        : const Color(0xFFFF9100),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (isConnected
                                ? const Color(0xFF00E676)
                                : const Color(0xFFFF9100))
                            .withOpacity(0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isConnected ? 'CONNECTED' : 'WAITING',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: isConnected
                        ? const Color(0xFF00E676)
                        : const Color(0xFFFF9100),
                  ),
                ),
                const SizedBox(width: 8),
                const SizedBox(
                  height: 12,
                  child: VerticalDivider(color: Color(0xFF2B374E), width: 1),
                ),
                const SizedBox(width: 8),
                // Transport Badge
                Icon(
                  isUsb ? Icons.usb_rounded : Icons.wifi_rounded,
                  size: 13,
                  color: isUsb
                      ? const Color(0xFFB388FF)
                      : const Color(0xFF00E5FF),
                ),
                const SizedBox(width: 4),
                Text(
                  '${state.localDevice.ipAddress}:${state.localDevice.port}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white70,
                    fontFamily: 'monospace',
                  ),
                ),
                if (isConnected && stats != null) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    height: 12,
                    child: VerticalDivider(color: Color(0xFF2B374E), width: 1),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${stats.fps.toStringAsFixed(0)} FPS',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00E5FF),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
