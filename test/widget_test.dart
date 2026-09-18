import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_3_47_4/main.dart';

void main() {
  testWidgets('BeamQrApp renders BeamHomeScreen and action cards',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BeamQrApp());

    // Verify app brand
    expect(find.text('BeamQR'), findsOneWidget);

    // Verify Sender and Receiver action cards
    expect(find.text('Beam Video (Send)'), findsOneWidget);
    expect(find.text('Scan & Receive'), findsOneWidget);
    expect(find.text('100% Offline P2P'), findsOneWidget);
  });
}
