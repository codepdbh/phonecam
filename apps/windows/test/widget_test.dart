import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phonecam_windows/main.dart';

void main() {
  testWidgets('PhoneCamWindowsApp smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const ProviderScope(
        child: PhoneCamWindowsApp(),
      ),
    );

    expect(find.text('PhoneCam'), findsOneWidget);
    expect(find.text('DEVICES'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
  });
}
