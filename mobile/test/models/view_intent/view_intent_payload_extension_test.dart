import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/models/view_intent/view_intent_payload.extension.dart';
import 'package:immich_mobile/platform/view_intent_api.g.dart';

void main() {
  test('normalizes provider display names', () {
    final cases = <({String path, String displayName, String expected})>[
      (path: '/tmp/view_intent_1.jpg', displayName: r'folder/subfolder\photo.jpg', expected: 'photo.jpg'),
      (path: '/tmp/view_intent_2.jpg', displayName: 'photo...', expected: 'photo.jpg'),
      (path: '/tmp/view_intent_3.jpg', displayName: 'photo', expected: 'photo.jpg'),
      (path: '/tmp/view_intent_4.jpg', displayName: 'photo.2026', expected: 'photo.2026.jpg'),
      (path: '/tmp/view_intent_5.tmp', displayName: 'photo.png', expected: 'photo.png'),
    ];

    for (final testCase in cases) {
      final payload = ViewIntentPayload(
        path: testCase.path,
        mimeType: 'image/jpeg',
        displayName: testCase.displayName,
        checksum: 'checksum',
      );

      expect(payload.fileName, testCase.expected, reason: testCase.displayName);
    }
  });
}
