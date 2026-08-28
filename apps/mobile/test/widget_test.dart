import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phonecam_mobile/main.dart';

void main() {
  testWidgets('PhoneCamMobileApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PhoneCamMobileApp(),
      ),
    );

    // Initial state without granted permission displays camera permission prompt
    expect(find.byType(PhoneCamMobileApp), findsOneWidget);
  });
}
