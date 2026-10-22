import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';

void main() {
  testWidgets('App renders title and language toggle', (WidgetTester tester) async {
    await tester.pumpWidget(const AiVideoEditorApp());

    expect(find.text('.edit'), findsOneWidget);
    expect(find.byIcon(Icons.language), findsOneWidget);
  });
}
