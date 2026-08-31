import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import '../../native/virtual_camera_bridge.dart';
import '../../providers/connection_provider.dart';
import 'manual_ip_dialog.dart';

class DevicesSidebar extends ConsumerWidget {
  const DevicesSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(phoneCamProvider);
    final notifier = ref.read(phoneCamProvider.notifier);

    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: Color(0xFF0F141C),
        border: Border(
          right: BorderSide(color: Color(0xFF1E2638), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/icono.png',
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PhoneCam',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'Virtual Camera Studio',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF1E2638), height: 1),

          // Discovered Section Title
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'DEVICES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8B949E),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF21262D),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${state.discoveredDevices.length}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF58A6FF),
                        ),
                      ),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Connect by IP',
                  icon: const Icon(Icons.add_link_rounded,
                      size: 18, color: Color(0xFF8B949E)),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => const ManualIpDialog(),
                    );
                  },
                ),
              ],
            ),
          ),

          // Devices List
          Expanded(
            child: state.discoveredDevices.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                Color(0xFF00E5FF),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Scanning network...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Open PhoneCam on your phone to connect.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: state.discoveredDevices.length,
                    itemBuilder: (context, index) {
                      final device = state.discoveredDevices[index];
                      final isConnected =
                          state.connectedDevice?.id == device.id &&
                              state.connectionState.isConnectedOrStreaming;

                      return _DeviceCard(
                        device: device,
                        isConnected: isConnected,
                        onConnect: () => notifier.connect(device),
                        onDisconnect: () => notifier.disconnect(),
                      );
                    },
                  ),
          ),

          // Driver Registration / Verification Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: const Color(0xFF00E5FF),
                side: const BorderSide(color: Color(0xFF00E5FF), width: 1),
                minimumSize: const Size.fromHeight(38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.verified_user_rounded,
                  size: 16, color: Color(0xFF00E5FF)),
              label: const Text(
                'Instalar / Reparar Driver',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                final bridge = VirtualCameraBridge.instance;
                var result = bridge.initialize();
                if (result != 0 && Platform.isWindows) {
                  final directory =
                      File(Platform.resolvedExecutable).parent.path;
                  final script = '$directory\\install_virtual_camera.ps1';
                  final dll = '$directory\\PhoneCamMediaSource_v7.dll';
                  if (File(script).existsSync() && File(dll).existsSync()) {
                    final process = await Process.run('powershell.exe', [
                      '-NoProfile',
                      '-ExecutionPolicy',
                      'Bypass',
                      '-File',
                      script,
                      '-SkipBuild',
                      '-SourceDll',
                      dll,
                    ]);
                    if (process.exitCode == 0) result = bridge.initialize();
                  }
                }
                if (!context.mounted) return;
                final success = result == 0;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: success
                        ? const Color(0xFF10B981)
                        : const Color(0xFFDC2626),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    content: Row(
                      children: [
                        Icon(
                          success
                              ? Icons.check_circle_rounded
                              : Icons.error_rounded,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            success
                                ? 'Cámara virtual instalada y verificada correctamente.'
                                : 'No se pudo instalar la cámara (estado $result, HRESULT 0x${bridge.lastHResult.toRadixString(16)}).',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Bottom Quick Manual IP Action
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF58A6FF),
                side: const BorderSide(color: Color(0xFF30363D)),
                minimumSize: const Size.fromHeight(38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.dialpad_rounded, size: 15),
              label: const Text('Manual IP Connect',
                  style: TextStyle(fontSize: 12)),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => const ManualIpDialog(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final DeviceInfo device;
  final bool isConnected;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _DeviceCard({
    required this.device,
    required this.isConnected,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final isUsb = device.transportType == TransportType.usbTethering;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isConnected ? const Color(0xFF16243A) : const Color(0xFF151A24),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF00E5FF).withValues(alpha: 0.5)
              : const Color(0xFF222B3D),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.smartphone_rounded,
                size: 18,
                color: isConnected ? const Color(0xFF00E5FF) : Colors.white70,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  device.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Transport Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isUsb
                      ? const Color(0xFF7C4DFF).withValues(alpha: 0.2)
                      : const Color(0xFF00E676).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: isUsb
                        ? const Color(0xFF7C4DFF).withValues(alpha: 0.5)
                        : const Color(0xFF00E676).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isUsb ? Icons.usb_rounded : Icons.wifi_rounded,
                      size: 11,
                      color: isUsb
                          ? const Color(0xFFB388FF)
                          : const Color(0xFF00E676),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      isUsb ? 'USB' : 'Wi-Fi',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isUsb
                            ? const Color(0xFFB388FF)
                            : const Color(0xFF00E676),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${device.ipAddress}:${device.port}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.4),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 30,
            child: isConnected
                ? ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFFFF5252).withValues(alpha: 0.2),
                      foregroundColor: const Color(0xFFFF5252),
                      elevation: 0,
                      side: const BorderSide(color: Color(0xFFFF5252)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    icon: const Icon(Icons.link_off_rounded, size: 14),
                    label: const Text('Disconnect',
                        style: TextStyle(fontSize: 12)),
                    onPressed: onDisconnect,
                  )
                : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: const Color(0xFF0F141C),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    icon: const Icon(Icons.link_rounded, size: 14),
                    label: const Text(
                      'Connect',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    onPressed: onConnect,
                  ),
          ),
        ],
      ),
    );
  }
}
