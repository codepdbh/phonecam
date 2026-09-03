import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/connection_provider.dart';
import '../../services/driver_installer_service.dart';

/// Tells the user up front whether the native virtual-camera driver is
/// installed and what to expect from it on this Windows version, instead of
/// letting them discover it only after "Activate Virtual Camera" silently
/// fails or the camera never shows up in Meet/Zoom.
class DriverStatusBanner extends ConsumerWidget {
  const DriverStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(phoneCamProvider);
    final notifier = ref.read(phoneCamProvider.notifier);

    switch (state.driverStatus) {
      case DriverStatus.checking:
      case DriverStatus.unsupportedPlatform:
      case DriverStatus.frameServerCapable:
        return _MessageOnly(message: state.driverInstallMessage);
      case DriverStatus.notInstalled:
        return _Banner(
          color: const Color(0xFF3A1F1F),
          borderColor: const Color(0xFF7A3A3A),
          icon: Icons.error_outline_rounded,
          iconColor: const Color(0xFFFF6B6B),
          title: 'Driver de cámara virtual no instalado',
          detail:
              'Sin esto, PhoneCam no va a aparecer como cámara en Meet, Zoom, '
              'OBS ni Python/OpenCV. Se necesita instalar un componente de '
              'Windows una sola vez (pide permisos de administrador).',
          message: state.driverInstallMessage,
          action: ElevatedButton.icon(
            onPressed: state.isInstallingDriver ? null : notifier.installDriver,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B6B),
              foregroundColor: const Color(0xFF1A0000),
            ),
            icon: state.isInstallingDriver
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF1A0000)),
                  )
                : const Icon(Icons.download_rounded, size: 18),
            label: Text(
                state.isInstallingDriver ? 'Instalando...' : 'Instalar ahora'),
          ),
        );
      case DriverStatus.dshowOnly:
        return _Banner(
          color: const Color(0xFF1F2A3A),
          borderColor: const Color(0xFF3A4F7A),
          icon: Icons.info_outline_rounded,
          iconColor: const Color(0xFF6BA3FF),
          title: 'Modo compatibilidad (sin Windows 11 Frame Server)',
          detail:
              'La cámara funciona en Zoom, OBS, navegadores y Python/OpenCV, '
              'pero apps que solo usan la cámara moderna de Windows 11 '
              '(22H2+) no la van a listar. Actualiza Windows para el soporte completo.',
          message: state.driverInstallMessage,
          action: null,
        );
    }
  }
}

class _MessageOnly extends StatelessWidget {
  final String? message;
  const _MessageOnly({this.message});

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.isEmpty) return const SizedBox.shrink();
    return _Banner(
      color: const Color(0xFF1F3A24),
      borderColor: const Color(0xFF3A7A4F),
      icon: Icons.check_circle_outline_rounded,
      iconColor: const Color(0xFF6BFF9E),
      title: 'Driver de cámara virtual',
      detail: message!,
      message: null,
      action: null,
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String detail;
  final String? message;
  final Widget? action;

  const _Banner({
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.detail,
    required this.message,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        border: Border(bottom: BorderSide(color: borderColor, width: 1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
                if (message != null && message!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    message!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 12),
            action!,
          ],
        ],
      ),
    );
  }
}
