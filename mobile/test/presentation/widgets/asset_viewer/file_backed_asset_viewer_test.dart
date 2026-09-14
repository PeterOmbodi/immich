import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/file_backed_asset_viewer.widget.dart';

void main() {
  testWidgets('shows only file preview navigation and upload controls', (tester) async {
    final asset = FileBackedAsset(
      path: 'C:/cache/preview.png',
      checksum: 'checksum',
      name: 'preview.png',
      type: AssetType.image,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: FileBackedAssetViewer(asset: asset, onUpload: () async {}),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.backup_outlined), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
