import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mama_ai/core/widgets/selection_toolbar.dart';

void main() {
  testWidgets('text selection only offers MamaBot actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        // Pin Android so the Material selection toolbar is built, no matter
        // which desktop the tests run on.
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Center(
            child: SelectableText(
              'Hello MamaBot',
              contextMenuBuilder: buildMamaSelectionToolbar,
            ),
          ),
        ),
      ),
    );

    await tester.longPress(find.byType(SelectableText));
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);

    // These are injected by installed Android apps through ACTION_PROCESS_TEXT.
    // MamaBot must never hand the person to another AI or app from here.
    expect(find.text('Ask Claude'), findsNothing);
    expect(find.text('Ask Gemini'), findsNothing);
    expect(find.text('Open in Bible'), findsNothing);
  });
}
