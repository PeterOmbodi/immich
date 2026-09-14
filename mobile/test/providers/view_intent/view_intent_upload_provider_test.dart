import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/providers/view_intent/view_intent_upload.provider.dart';
import 'package:immich_mobile/services/foreground_upload.service.dart';
import 'package:immich_mobile/services/view_intent.service.dart';
import 'package:mocktail/mocktail.dart';

import '../../service.mocks.dart';

class MockViewIntentService extends Mock implements ViewIntentService {}

void main() {
  late ProviderContainer container;
  late MockForegroundUploadService uploadService;
  late MockViewIntentService viewIntentService;

  final asset = FileBackedAsset(
    path: 'C:/cache/view_intent.jpg',
    checksum: 'checksum',
    name: 'view_intent.jpg',
    type: AssetType.image,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );

  setUpAll(() => registerFallbackValue(const UploadCallbacks()));

  setUp(() {
    uploadService = MockForegroundUploadService();
    viewIntentService = MockViewIntentService();
    container = ProviderContainer(
      overrides: [
        foregroundUploadServiceProvider.overrideWithValue(uploadService),
        viewIntentServiceProvider.overrideWithValue(viewIntentService),
      ],
    );
    addTearDown(container.dispose);
  });

  test('uploads the backing file and maps callbacks to the asset id', () async {
    final progress = <(String, int, int)>[];
    final succeeded = <(String, String)>[];
    when(() => viewIntentService.markUploadActive(asset.path)).thenReturn(null);
    when(() => viewIntentService.markUploadInactive(asset.path)).thenAnswer((_) async {});
    when(
      () => uploadService.uploadShareIntent(
        any(),
        cancelToken: any(named: 'cancelToken'),
        onProgress: any(named: 'onProgress'),
        onSuccess: any(named: 'onSuccess'),
        onError: any(named: 'onError'),
      ),
    ).thenAnswer((invocation) async {
      final onProgress = invocation.namedArguments[#onProgress] as void Function(String, int, int)?;
      final onSuccess = invocation.namedArguments[#onSuccess] as void Function(String, String)?;
      onProgress?.call('file-id', 5, 10);
      onSuccess?.call('file-id', 'remote-id');
    });

    await container
        .read(viewIntentUploadProvider)
        .upload(
          asset: asset,
          cancelToken: Completer<void>(),
          callbacks: UploadCallbacks(
            onProgress: (id, _, bytes, total) => progress.add((id, bytes, total)),
            onSuccess: (id, remoteId) => succeeded.add((id, remoteId)),
          ),
        );

    final files =
        verify(
              () => uploadService.uploadShareIntent(
                captureAny(),
                cancelToken: any(named: 'cancelToken'),
                onProgress: any(named: 'onProgress'),
                onSuccess: any(named: 'onSuccess'),
                onError: any(named: 'onError'),
              ),
            ).captured.single
            as List<File>;
    expect(files.single.path, asset.path);
    expect(progress, [(asset.id, 5, 10)]);
    expect(succeeded, [(asset.id, 'remote-id')]);
    verify(() => viewIntentService.markUploadActive(asset.path)).called(1);
    verify(() => viewIntentService.markUploadInactive(asset.path)).called(1);
    verifyNever(
      () => uploadService.uploadManual(
        any(),
        cancelToken: any(named: 'cancelToken'),
        callbacks: any(named: 'callbacks'),
      ),
    );
  });

  test('keeps the backing file protected until a cancelled upload settles', () async {
    final cancelToken = Completer<void>();
    when(() => viewIntentService.markUploadActive(asset.path)).thenReturn(null);
    when(() => viewIntentService.markUploadInactive(asset.path)).thenAnswer((_) async {});
    when(
      () => uploadService.uploadShareIntent(
        any(),
        cancelToken: cancelToken,
        onProgress: any(named: 'onProgress'),
        onSuccess: any(named: 'onSuccess'),
        onError: any(named: 'onError'),
      ),
    ).thenAnswer((_) async => cancelToken.complete());

    await container
        .read(viewIntentUploadProvider)
        .upload(asset: asset, cancelToken: cancelToken, callbacks: const UploadCallbacks());

    verify(() => viewIntentService.markUploadActive(asset.path)).called(1);
    verify(() => viewIntentService.markUploadInactive(asset.path)).called(1);
  });

  test('maps upload errors to the asset id', () async {
    final errors = <(String, String)>[];
    when(() => viewIntentService.markUploadActive(asset.path)).thenReturn(null);
    when(() => viewIntentService.markUploadInactive(asset.path)).thenAnswer((_) async {});
    when(
      () => uploadService.uploadShareIntent(
        any(),
        cancelToken: any(named: 'cancelToken'),
        onProgress: any(named: 'onProgress'),
        onSuccess: any(named: 'onSuccess'),
        onError: any(named: 'onError'),
      ),
    ).thenAnswer((invocation) async {
      final onError = invocation.namedArguments[#onError] as void Function(String, String)?;
      onError?.call('file-id', 'boom');
    });

    await container
        .read(viewIntentUploadProvider)
        .upload(
          asset: asset,
          cancelToken: Completer<void>(),
          callbacks: UploadCallbacks(onError: (id, error) => errors.add((id, error))),
        );

    expect(errors, [(asset.id, 'boom')]);
    verify(() => viewIntentService.markUploadInactive(asset.path)).called(1);
  });
}
