import 'package:flutter_test/flutter_test.dart';
import 'package:solara_mobile/main.dart';

void main() {
  testWidgets('renders fallback UI when native WebView is unavailable',
      (tester) async {
    await tester.pumpWidget(const SolaraApp());
    expect(find.text('Solara player unavailable'), findsOneWidget);
  });
}
