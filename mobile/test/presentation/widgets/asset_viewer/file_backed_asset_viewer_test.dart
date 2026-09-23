import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/file_backed_asset_viewer.widget.dart';

import '../../../widget_tester_extensions.dart';

void main() {
  testWidgets('shows viewer chrome with an upload action', (tester) async {
    final asset = FileBackedAsset(
      path: 'C:/cache/preview.png',
      checksum: 'checksum',
      name: 'preview.png',
      type: AssetType.image,
      createdAt: DateTime(2025, 1, 2, 15, 4),
      updatedAt: DateTime(2025, 1, 2, 15, 4),
    );

    await tester.pumpConsumerWidget(FileBackedAssetViewer(asset: asset, onUpload: () async {}));

    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    expect(find.byIcon(Icons.backup_outlined), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);

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

  testWidgets('explains when the file cannot be previewed', (tester) async {
    final asset = FileBackedAsset(
      path: 'C:/cache/sample.cr3',
      checksum: 'checksum',
      name: 'sample.cr3',
      type: AssetType.image,
      createdAt: DateTime(2025, 1, 2, 15, 4),
      updatedAt: DateTime(2025, 1, 2, 15, 4),
    );

    await tester.pumpConsumerWidget(FileBackedAssetViewer(asset: asset, onUpload: () async {}));
    final imageFinder = find.byType(Image);
    final image = tester.widget<Image>(imageFinder);
    final error = image.errorBuilder!(tester.element(imageFinder), StateError('unsupported image'), StackTrace.empty);
    await tester.pumpConsumerWidget(error);

    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(find.text('Preview unavailable'), findsOneWidget);
    expect(find.text('sample.cr3'), findsOneWidget);
  });
}
