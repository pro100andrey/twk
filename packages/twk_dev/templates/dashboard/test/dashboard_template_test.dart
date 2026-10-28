import 'package:dashboard_template/dashboard_template.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('the panels show the first readings', (t) async {
    await t.pumpWidget(const Dashboard(), size: (80, 20));
    expect(t, containsLine(contains('╭ CPU ${cpuAt(0).round()}% ')));
    expect(t, containsLine(contains('${(memoryAt(0) * 100).round()}% ─')));
    expect(find.byType(Chart), findsOneWidget);
    for (final service in services) {
      expect(t, containsLine(contains(service)));
    }
    expect(t, containsLine('p pause   q quit'));
  });

  testTwk('a reading each second, the newest shown', (t) async {
    await t.pumpWidget(const Dashboard(), size: (80, 20));
    await t.pump(interval * 3);
    expect(t, containsLine(contains('╭ CPU ${cpuAt(3).round()}% ')));
    expect(t, containsLine(endsWith('live, 3s')));
  });

  testTwk('p pauses the readings and resumes them', (t) async {
    await t.pumpWidget(const Dashboard(), size: (80, 20));
    await t.pump(interval * 2);
    await t.press('p');
    await t.pump(interval * 5);
    expect(t, containsLine(endsWith('paused at 2s')));
    expect(t, containsLine('p resume   q quit'));

    await t.press('p');
    await t.pump(interval);
    expect(t, containsLine(endsWith('live, 3s')));
  });

  testTwk('q quits', (t) async {
    await t.pumpWidget(const Dashboard());
    await t.press('q');
    expect(t.isRunning, isFalse);
  });
}
