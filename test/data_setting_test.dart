import 'package:flutter_test/flutter_test.dart';
import 'package:ihateperfume/screens/data_setting.dart';

void main() {
  test('checked text', () {
    final now = DateTime(2026, 10, 4, 18);
    expect(checkedText(null), 'Not checked yet');
    expect(checkedText(now.subtract(const Duration(seconds: 20)), now: now), 'Checked just now');
    expect(checkedText(now.subtract(const Duration(minutes: 5)), now: now), 'Checked 5 min ago');
    expect(checkedText(now.subtract(const Duration(hours: 1)), now: now), 'Checked 1 hour ago');
    expect(checkedText(now.subtract(const Duration(hours: 3)), now: now), 'Checked 3 hours ago');
    expect(checkedText(DateTime(2026, 10, 1), now: now), 'Checked Oct 1');
  });
}
