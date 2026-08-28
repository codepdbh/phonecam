import 'package:flutter/material.dart';
import 'widgets/devices_sidebar.dart';
import 'widgets/video_stage.dart';
import 'widgets/telemetry_bottom_bar.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF090D13),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // Left Panel: Discovered Phones list
                DevicesSidebar(),
                // Main Panel: Camera Preview stage
                Expanded(child: VideoStage()),
              ],
            ),
          ),
          // Bottom Panel: Telemetry stats bar
          TelemetryBottomBar(),
        ],
      ),
    );
  }
}
