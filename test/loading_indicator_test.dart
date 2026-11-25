import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishare/shared/widgets/loading_indicator.dart';

void main() {
  testWidgets('renders a 48dp container with a 38dp morphing indicator', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: WiLoadingIndicator(reduceMotion: true)),
    );
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);

    final paints = tester.widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(WiLoadingIndicator),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(paints.length, 1);

    final boxes = tester.widgetList<SizedBox>(
      find.descendant(
        of: find.byType(WiLoadingIndicator),
        matching: find.byType(SizedBox),
      ),
    );
    expect(boxes.any((box) => box.width == 48 && box.height == 48), isTrue);
    expect(
      boxes.any((box) => box.width == 38 && box.height == 38),
      isTrue,
      reason: 'active indicator is 38dp inside a 48dp container',
    );
  });

  testWidgets('reduced motion keeps the indicator stable', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: WiLoadingIndicator(reduceMotion: true)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(WiLoadingIndicator),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });
}
