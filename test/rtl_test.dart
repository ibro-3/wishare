import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishare/shared/widgets/directional_icon.dart';

void main() {
  testWidgets('directional icons mirror in RTL but not LTR', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: WiDirectionalIcon(Icons.send),
      ),
    );
    expect(find.byType(Transform), findsNothing);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: WiDirectionalIcon(Icons.send),
      ),
    );
    final transforms = tester.widgetList<Transform>(find.byType(Transform));
    expect(
      transforms.any(
        (transform) =>
            transform.transform.storage[0] == -1 &&
            transform.transform.storage[5] == 1,
      ),
      isTrue, // horizontal mirror only, no vertical flip
    );
  });

  testWidgets('non-directional icons are never mirrored', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: WiDirectionalIcon(Icons.check, mirrored: false),
      ),
    );
    expect(find.byType(Transform), findsNothing);
  });
}
