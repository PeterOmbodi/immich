import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/presentation/actions/action.dart';
import 'package:immich_mobile/presentation/actions/action.widget.dart';
import 'package:immich_mobile/presentation/actions/file_backed_upload.action.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/providers/view_intent/view_intent_upload.provider.dart';
import 'package:immich_mobile/services/foreground_upload.service.dart';
import 'package:immich_mobile/utils/asset_filter.dart';
import 'package:immich_ui/immich_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../presentation_context.dart';

class MockViewIntentUpload extends Mock implements ViewIntentUpload {}

void main() {
  late PresentationContext context;
  late MockViewIntentUpload upload;

  final asset = FileBackedAsset(
    path: 'C:/cache/view_intent.jpg',
    checksum: 'checksum',
    name: 'view_intent.jpg',
    type: AssetType.image,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );

  setUpAll(() {
    registerFallbackValue(Completer<void>());
    registerFallbackValue(const UploadCallbacks());
  });

  setUp(() async {
    context = await PresentationContext.create();
    upload = MockViewIntentUpload();
  });

  tearDown(() async {
    await context.dispose();
  });

  testWidgets('uploads a file-backed viewer asset', (tester) async {
    when(
      () => upload.upload(
        asset: asset,
        cancelToken: any(named: 'cancelToken'),
        callbacks: any(named: 'callbacks'),
      ),
    ).thenAnswer((invocation) async {
      final callbacks = invocation.namedArguments[#callbacks] as UploadCallbacks;
      callbacks.onSuccess?.call(asset.id, 'remote-id');
    });

    await tester.pumpTestWidget(
      context,
      const ActionIconButton(action: FileBackedUploadAction(source: ActionSource.viewer)),
      overrides: [
        assetsActionProvider(ActionSource.viewer).overrideWithValue(AssetFilter<BaseAsset>({asset})),
        viewIntentUploadProvider.overrideWithValue(upload),
        toastServiceProvider.overrideWithValue(context.service.toast),
      ],
    );

    await tester.tap(find.byType(ImmichIconButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    verify(
      () => upload.upload(
        asset: asset,
        cancelToken: any(named: 'cancelToken'),
        callbacks: any(named: 'callbacks'),
      ),
    ).called(1);
  });

  testWidgets('cancels a file-backed upload from the progress dialog', (tester) async {
    late Completer<void> cancelToken;
    when(
      () => upload.upload(
        asset: asset,
        cancelToken: any(named: 'cancelToken'),
        callbacks: any(named: 'callbacks'),
      ),
    ).thenAnswer((invocation) async {
      cancelToken = invocation.namedArguments[#cancelToken] as Completer<void>;
      await cancelToken.future;
    });

    await tester.pumpTestWidget(
      context,
      const ActionIconButton(action: FileBackedUploadAction(source: ActionSource.viewer)),
      overrides: [
        assetsActionProvider(ActionSource.viewer).overrideWithValue(AssetFilter<BaseAsset>({asset})),
        viewIntentUploadProvider.overrideWithValue(upload),
        toastServiceProvider.overrideWithValue(context.service.toast),
      ],
    );

    await tester.tap(find.byType(ImmichIconButton));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.byType(ImmichTextButton));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));

    expect(cancelToken.isCompleted, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    verifyNever(() => context.service.toast.error(any()));
  });
}
