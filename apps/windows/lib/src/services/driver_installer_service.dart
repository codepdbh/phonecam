import 'dart:io';
import 'package:flutter/foundation.dart';
import '../native/virtual_camera_bridge.dart';

/// Coarse status of the native virtual-camera driver on this machine.
enum DriverStatus {
  /// Still probing (initial state before the first check completes).
  checking,

  /// Not on Windows — the native driver does not apply.
  unsupportedPlatform,

  /// The native DLL isn't registered machine-wide yet: the installer has
  /// never run (or ran and failed). The virtual camera will not appear in
  /// any other app until this is fixed.
  notInstalled,

  /// Registered, but this Windows build has no Media Foundation Frame
  /// Server (mfsensorgroup.dll / MFCreateVirtualCamera — Windows 11 22H2+
  /// only). The DirectShow source still works standalone: Zoom, OBS,
  /// classic Chromium camera pickers and OpenCV's DSHOW backend will see
  /// it, but apps that only enumerate cameras through the modern Windows
  /// 11 camera stack will not.
  dshowOnly,

  /// Fully registered and this Windows build supports the Frame Server
  /// virtual camera too — every consumer should see it.
  frameServerCapable,
}

class DriverInstallResult {
  final bool success;
  final String message;
  const DriverInstallResult(this.success, this.message);
}

/// Detects whether the PhoneCam virtual-camera driver is installed and, if
/// not, runs the (self-elevating) installer script bundled next to the app.
class DriverInstallerService {
  static const _dllName = 'PhoneCamMediaSource_v7.dll';
  static const _scriptName = 'install_virtual_camera.ps1';

  DriverStatus check() {
    if (!Platform.isWindows) return DriverStatus.unsupportedPlatform;
    final bridge = VirtualCameraBridge.instance;
    if (!bridge.isLoaded || !bridge.isRegistered) {
      return DriverStatus.notInstalled;
    }
    return bridge.supportsFrameServer
        ? DriverStatus.frameServerCapable
        : DriverStatus.dshowOnly;
  }

  Future<DriverInstallResult> install() async {
    if (!Platform.isWindows) {
      return const DriverInstallResult(
          false, 'La cámara virtual solo está disponible en Windows.');
    }
    final scriptPath = _resolveNear(_scriptName);
    if (scriptPath == null) {
      return const DriverInstallResult(false,
          'No se encontró install_virtual_camera.ps1 junto al ejecutable. '
          'Reinstala PhoneCam o ejecuta el script manualmente desde la '
          'carpeta scripts/ del proyecto.');
    }

    final args = <String>['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath];
    final dllPath = _resolveNear(_dllName);
    if (dllPath != null) {
      // Ship a prebuilt DLL next to the exe: end users don't have the C++
      // toolchain the script would otherwise try to build with.
      args.addAll(['-SkipBuild', '-SourceDll', dllPath]);
    }

    debugPrint('[DRIVER_INSTALL] Running: powershell.exe ${args.join(' ')}');
    try {
      final result = await Process.run('powershell.exe', args, runInShell: false);
      final output = '${result.stdout}\n${result.stderr}'.trim();
      if (result.exitCode == 0) {
        return DriverInstallResult(
            true, output.isEmpty ? 'Instalación completada.' : output);
      }
      // A cancelled UAC prompt or a script failure both land here.
      return DriverInstallResult(
          false,
          output.isEmpty
              ? 'La instalación falló (código ${result.exitCode}). '
                  'Si cancelaste el aviso de permisos de Windows, intenta de nuevo y acepta la elevación.'
              : output);
    } catch (e) {
      return DriverInstallResult(false, 'No se pudo iniciar el instalador: $e');
    }
  }

  /// Looks for [fileName] next to the running executable first (the layout
  /// a packaged release ships), then walks up from there looking for
  /// `scripts/<fileName>` or `native/windows/virtual_camera/build/Release/<fileName>`
  /// so `flutter run` from a source checkout also works during development.
  String? _resolveNear(String fileName) {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final direct = File('${exeDir.path}\\$fileName');
    if (direct.existsSync()) return direct.path;

    Directory dir = exeDir;
    for (var i = 0; i < 10; i++) {
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
      final scriptsCandidate = File('${dir.path}\\scripts\\$fileName');
      if (scriptsCandidate.existsSync()) return scriptsCandidate.path;
      final dllCandidate = File(
          '${dir.path}\\native\\windows\\virtual_camera\\build\\Release\\$fileName');
      if (dllCandidate.existsSync()) return dllCandidate.path;
    }
    return null;
  }
}
