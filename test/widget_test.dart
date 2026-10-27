import 'package:flutter_test/flutter_test.dart';
import 'package:daily_planner/main.dart';

void main() {
  testWidgets('shows Arabic planner home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DailyPlannerApp());
    expect(find.text('جدولي اليومي'), findsOneWidget);
  });
}
