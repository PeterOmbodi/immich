import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/file_backed_asset_viewer.widget.dart';
import 'package:intl/intl.dart';

import '../../../widget_tester_extensions.dart';

void main() {
  late String? originalLocale;

  setUpAll(() {
    originalLocale = Intl.defaultLocale;
    Intl.defaultLocale = 'en_US';
  });

  tearDownAll(() => Intl.defaultLocale = originalLocale);

  testWidgets('matches the standard viewer chrome with a centered upload action', (tester) async {
    final asset = FileBackedAsset(
      path: 'C:/cache/preview.png',
      checksum: 'checksum',
      name: 'preview.png',
      type: AssetType.image,
      createdAt: DateTime(2025, 1, 2, 15, 4),
      updatedAt: DateTime(2025, 1, 2, 15, 4),
    );

    await tester.pumpConsumerWidget(FileBackedAssetViewer(asset: asset, onUpload: () async {}));

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.text('Jan 2, 2025'), findsOneWidget);
    expect(find.textContaining('3:04'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    expect(find.byIcon(Icons.backup_outlined), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);

    final screenCenter = tester.getCenter(find.byType(Scaffold)).dx;
    expect(tester.getCenter(find.text('Upload')).dx, closeTo(screenCenter, 1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('offers only info in the overflow menu and opens file details', (tester) async {
    final asset = FileBackedAsset(
      path: 'C:/cache/preview.png',
      checksum: 'checksum',
      name: 'preview.png',
      type: AssetType.image,
      createdAt: DateTime(2025, 1, 2, 15, 4),
      updatedAt: DateTime(2025, 1, 2, 15, 4),
    );

    await tester.pumpConsumerWidget(FileBackedAssetViewer(asset: asset, onUpload: () async {}));

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Info'), findsOneWidget);
    expect(find.text('Slideshow'), findsNothing);

    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();

    expect(find.text('preview.png'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
