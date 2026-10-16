import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app has no remote fonts or session replay SDK', () {
    final pubspec = File('pubspec.yaml').readAsStringSync().toLowerCase();
    final dartSource = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync().toLowerCase())
        .join('\n');
    final inspected = '$pubspec\n$dartSource';

    expect(inspected, isNot(contains('fonts.googleapis.com')));
    expect(inspected, isNot(contains('fonts.gstatic.com')));
    expect(pubspec, isNot(contains('google_fonts:')));

    for (final replaySdk in [
      'fullstory',
      'smartlook',
      'logrocket',
      'hotjar',
      'clarity_flutter',
      'posthog_flutter',
      'sentry_flutter',
    ]) {
      expect(pubspec, isNot(contains('$replaySdk:')));
    }
  });
}
