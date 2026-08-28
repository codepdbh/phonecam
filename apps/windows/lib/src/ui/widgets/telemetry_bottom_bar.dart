import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import '../../providers/connection_provider.dart';

class TelemetryBottomBar extends ConsumerWidget {
  const TelemetryBottomBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(phoneCamProvider);
    final stats = state.stats;
    final isStreaming = state.connectionState == AppConnectionState.streaming;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0C1017),
        border: Border(
          top: BorderSide(color: Color(0xFF1B2332), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Connection State Pill
          _buildStateIndicator(state.connectionState),
          const SizedBox(width: 14),
          const VerticalDivider(
            color: Color(0xFF1E283A),
            indent: 12,
            endIndent: 12,
          ),
          const SizedBox(width: 14),

          // Telemetry Stats (Scrollable if constrained)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (isStreaming && stats != null) ...[
                    _buildStatItem(
                      icon: Icons.aspect_ratio_rounded,
                      label: 'Resolution',
                      value: stats.resolutionLabel,
                      valueColor: const Color(0xFF58A6FF),
                    ),
                    const SizedBox(width: 18),
                    _buildStatItem(
                      icon: Icons.speed_rounded,
                      label: 'FPS',
                      value: stats.fps.toStringAsFixed(0),
                      valueColor: const Color(0xFF00E5FF),
                    ),
                    const SizedBox(width: 18),
                    _buildStatItem(
                      icon: Icons.timelapse_rounded,
                      label: 'Latency',
                      value: '${stats.latencyMs} ms',
                      valueColor: stats.latencyMs < 50
                          ? const Color(0xFF00E676)
                          : const Color(0xFFFFD600),
                    ),
                    const SizedBox(width: 18),
                    _buildStatItem(
                      icon: Icons.network_check_rounded,
                      label: 'Bitrate',
                      value: stats.formattedBitrate,
                      valueColor: const Color(0xFFB388FF),
                    ),
                    const SizedBox(width: 18),
                    _buildStatItem(
                      icon: Icons.movie_filter_rounded,
                      label: 'Codec',
                      value: stats.codec.name.toUpperCase(),
                      valueColor: Colors.white70,
                    ),
                  ] else ...[
                    Text(
                      'No active telemetry stream',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.35),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Virtual Camera Device Tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: state.isVirtualCameraActive
                  ? const Color(0xFF00E676).withOpacity(0.12)
                  : const Color(0xFF1A2233),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: state.isVirtualCameraActive
                    ? const Color(0xFF00E676).withOpacity(0.4)
                    : const Color(0xFF28344E),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.camera_alt_rounded,
                  size: 13,
                  color: state.isVirtualCameraActive
                      ? const Color(0xFF00E676)
                      : Colors.white54,
                ),
                const SizedBox(width: 5),
                Text(
                  'PhoneCam Virtual Camera: ${state.isVirtualCameraActive ? "LIVE" : "OFFLINE"}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: state.isVirtualCameraActive
                        ? const Color(0xFF00E676)
                        : Colors.white60,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateIndicator(AppConnectionState state) {
    Color color;
    switch (state) {
      case AppConnectionState.streaming:
        color = const Color(0xFF00E676);
        break;
      case AppConnectionState.connected:
        color = const Color(0xFF00E5FF);
        break;
      case AppConnectionState.connecting:
      case AppConnectionState.pairing:
      case AppConnectionState.reconnecting:
        color = const Color(0xFFFFD600);
        break;
      case AppConnectionState.error:
        color = const Color(0xFFFF5252);
        break;
      default:
        color = const Color(0xFF8B949E);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              if (state == AppConnectionState.streaming)
                BoxShadow(
                  color: color.withOpacity(0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
            ],
          ),
        ),
        const SizedBox(width: 7),
        Text(
          state.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white38),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withOpacity(0.4),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: valueColor,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
