import 'package:flutter_test/flutter_test.dart';

import 'package:spielbergo_example/main.dart';

void main() {
  testWidgets('shows video editor launcher', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Open video editor'), findsOneWidget);
  });
}
