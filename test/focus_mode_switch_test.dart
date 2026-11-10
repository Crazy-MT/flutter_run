import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_run/focus_mode_switch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tap and drag update the native switch', (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FocusModeSwitch(onChanged: changes.add)),
    ));

    final control = find.bySemanticsLabel('专注模式');
    await tester.tap(control);
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(changes, [true]);

    final gesture = await tester.startGesture(tester.getCenter(control));
    for (var i = 0; i < 14; i++) {
      await gesture.moveBy(const Offset(-12, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    expect(changes, [true, false]);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard advances in four-percent steps', (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FocusModeSwitch(onChanged: changes.add)),
    ));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    expect(changes, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(changes, [true]);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
