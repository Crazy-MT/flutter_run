import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_run/log_filter.dart';

void main() {
  test('filters Android priority and keyword', () {
    expect(
        matchesLog('11-06 14:00:00.000  123  123 E Tag: broken', 'broken', 'W'),
        isTrue);
    expect(
        matchesLog('11-06 14:00:00.000  123  123 D Tag: broken', 'broken', 'W'),
        isFalse);
    expect(
        matchesLog('11-06 14:00:00.000  123  123 E Tag: broken', 'other', 'V'),
        isFalse);
  });
}
