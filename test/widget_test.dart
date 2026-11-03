import 'package:flutter_test/flutter_test.dart';
import 'package:motoalert/app.dart';

void main() {
  testWidgets('MotoAlertApp smoke test and navigation tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MotoAlertApp());
    await tester.pump();

    // Verify app title and navigation bar labels
    expect(find.text('MotoAlert'), findsWidgets);
    expect(find.text('Radar'), findsOneWidget);
    expect(find.text('LCD Text'), findsOneWidget);
    expect(find.text('Pengaturan'), findsOneWidget);
  });
}
